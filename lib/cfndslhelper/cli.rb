require 'yaml'
require 'fileutils'
require 'cfndsl'
require 'aws-sdk'
require 'json'
require 'trollop'

module CfnDSLHelper
  class Cli
    def initialize(argv, stdin=STDIN, stdout=STDOUT, stderr=STDERR, kernel=Kernel)
      @argv, @stdin, @stdout, @stderr, @kernel = argv, stdin, stdout, stderr, kernel
    end

    def execute!
      instruction = @argv.first
      puts "#CfnDSLHelperVERSION:#{CfnDSLHelper::VERSION}"
      get_config unless instruction == 'parameter-update'

      if instruction == 'generate'
        generate
      end

      if instruction == 'validate'
        validate
      end

      if instruction == 'upload'
        upload
      end

      if instruction == 'create'
        create
      end

      if instruction == 'delete'
        delete
      end

      if instruction == 'update'
        update
      end

      if instruction == 'show-events'
        show_events
      end

      if instruction == 'parameter-update'
        parameter_only_update
      end
    end

    def get_config
      @base_dir = ENV['CFN_BASE_DIR'] || Dir.pwd

      puts @base_dir

      @config = {}

      @extras = []

      config_location = ENV['CFN_CONFIG_LOCATION'] || "#{@base_dir}/config/project_config.yml"

      notifications_location = ENV['CFN_NOTIFICATIONS_LOCATION'] || "#{@base_dir}/config/notifications.yml"

      @config = YAML.load_file(config_location)

      if File.file? notifications_location
        @config.merge!(YAML.load_file(notifications_location))
      end

      parse_args

      if ENV['CFN_VERSION']
        @config['version'] = ENV['CFN_VERSION']
        File.write("#{@base_dir}/config/version.yml", "version: \"#{ENV['CFN_VERSION']}\"")
      end

      @config['region'] = @config['region'] || 'ap-southeast-2'

      %w[version pplication_name project].each do | requirement |
        raise "No #{requirement} specified" unless @config[requirement]
      end

      @cfn_templates = Dir["#{@base_dir}/cfndsl/**/*.rb"]

      if File.directory? "#{@base_dir}/cfndsl-imports"
        @cfn_templates += Dir["#{@base_dir}/cfndsl-imports/**/*.rb"]
      end

      Dir["#{@base_dir}/config/*.yml"].each do | extra |
        @extras << [:yaml, extra]
      end

      Dir["#{@base_dir}/config/*.rb"].each do | extra |
        @extras << [:ruby, extra]
      end

      if ENV['STACK_NAME']
        @config['stack_name'] = @config['stack_name'] || ENV['STACK_NAME']
      end

      puts @config
    end

    def get_config_no_files
      @config = {}
      parse_args
      @config['stack_name'] = @config['stack_name'] || ENV['STACK_NAME']
      @config['region'] = @config['region'] ||  ENV['AWS_DEFAULT_REGION'] || 'ap-southeast-2'
      puts @config
    end

    def parse_args
      options = Trollop::options do
        opt :stack_name, "whats the name of the stack??", type: String, short: "-s"
        opt :parameters, "specify some parameters for create-ing or overriding k=v,k1=v1", type: String, short: "-p"
      end

      @config = options.merge @config
    end

    def generate
      FileUtils.rm_rf Dir.glob("#{@base_dir}/output/**/*.json")
      FileUtils.rm_rf Dir.glob("#{@base_dir}/output/**/*.yml")

      if File.directory? "#{@base_dir}/raw-imports"
        FileUtils.cp_r Dir.glob("#{@base_dir}/raw-imports/**/*.json"), "#{@base_dir}/output/"
        FileUtils.cp_r Dir.glob("#{@base_dir}/raw-imports/**/*.yml"),  "#{@base_dir}/output/"
      end

      @cfn_templates.each do |cfn_template|
        puts cfn_template
        filename = cfn_template
        template = cfn_template.gsub(/.*\//, '')
        output = template.gsub(/.rb$/,'.json')
        puts '#BEGIN MODEL GENERATE'
        model = CfnDsl.eval_file_with_extras(filename, @extras, verbose)

        File.open("#{@base_dir}/output/#{output}", "w") do | f |
          f.write(JSON.pretty_generate(model))
        end
      end
    end

    def validate
      cfn = Aws::CloudFormation::Client.new(region: @config['region'])

      Dir.glob("#{@base_dir}/output/*.json").each do | template |
        puts "will validate #{template}"
        body = File.read(template)

        resp = cfn.validate_template(
          template_body: body
        )
        puts resp
      end
    end

    def upload
      s3 = Aws::S3::Resource.new(region: @config['source_region'])
      Dir.glob("#{@base_dir}/output/*.json").each do | template |
        puts "will upload #{template}"
        key = template.gsub(/.*\//, '')
        key = "cloudformation/#{@config['project']}/#{@config['application_name']}/#{@config['version']}/#{key}"
        puts "will upload #{template} to #{key}"
        obj = s3.bucket(@config['source_bucket']).object(key)
        obj.upload_file(template)
      end
    end

    def get_parameters_to_array
      parameters = []
      if @config[:parameters_given]
        @config[:parameters].split(',').each { | p | interim = p.split('='); parameters << { parameter_key: interim[0], parameter_value: interim[1] } }
      end

      parameters
    end

    # https://docs.aws.amazon.com/sdkforruby/api/Aws/CloudFormation/Client.html#create_stack-instance_method
    def create
      puts @config['region']
      cfn = Aws::CloudFormation::Client.new(region: @config['region'])

      parameters = get_parameters_to_array
      puts parameters

      stack = {
        stack_name: @config[:stack_name],
        template_url: template_url,
        parameters: parameters,
        notification_arns: @config['notification_arns'],
        capabilities: ['CAPABILITY_IAM', 'CAPABILITY_NAMED_IAM'],
        tags: []
      }

      if @config[:set_stack_as_name_tag]
        stack[:tags] << { key: 'Name', value: @config[:stack_name]}
      end

      puts stack

      resp = cfn.create_stack(stack)

      puts resp

      stack_wait :stack_create_complete, {stack_name: @config[:stack_name] }
    end

    def delete
      cfn = Aws::CloudFormation::Client.new(region: @config['region'])
      resp = cfn.delete_stack({stack_name: @config[:stack_name]})
      puts resp

      stack_wait :stack_delete_complete, {stack_name: @config[:stack_name] }
    end

    def get_update_parameters(stack)
      update_parameters = []
      stack.parameters.each { |sp| update_parameters << sp.to_hash }

      override_parameters = get_parameters_to_array
      puts override_parameters

      override_parameters.each do | parameter |
        puts parameter
        if update_parameters.detect { | up | up[:parameter_key] == parameter[:parameter_key] }
          update_parameters.each { | up | up[:parameter_value] = parameter[:parameter_value] if up[:parameter_key] == parameter[:parameter_key] }
        else
          puts "#{parameter} not found in current parameters for stack"
          update_parameters << { parameter_key: parameter[:parameter_key], parameter_value: parameter[:parameter_value] }
        end
      end

      update_parameters.each { |x| p x }
    end

    def parameter_only_update
      get_config_no_files
      cfn = Aws::CloudFormation::Client.new(region: @config['region'])

      stack = cfn.describe_stacks({stack_name: @config[:stack_name]}).stacks[0]
      update_parameters = get_update_parameters(stack)

      puts update_parameters

      update_hash = {
        stack_name: @config[:stack_name],
        parameters:  update_parameters,
        notification_arns: @config['notification_arns'],
        use_previous_template: true,
        capabilities: ["CAPABILITY_NAMED_IAM"],
        tags: []
      }

      if @config[:set_stack_as_name_tag]
        update_hash[:tags] << { key: 'Name', value: @config[:stack_name]}
      end

      run_update update_hash
    end

    def update
      cfn = Aws::CloudFormation::Client.new(region: @config['region'])

      stack = cfn.describe_stacks({stack_name: @config[:stack_name]}).stacks[0]
      update_parameters = get_update_parameters(stack)

      puts update_parameters

      update_hash = {
        stack_name: @config[:stack_name],
        template_url: template_url,
        parameters:  update_parameters,
        notification_arns: @config['notification_arns'],
        capabilities: ["CAPABILITY_NAMED_IAM"],
        tags: []
      }

      if @config[:set_stack_as_name_tag]
        update_hash[:tags] << { key: 'Name', value: @config[:stack_name]}
      end

      run_update update_hash
    end

    def run_update(update_hash)
      cfn = Aws::CloudFormation::Client.new(region: @config['region'])
      puts "debug update_hash"
      puts update_hash

      resp = cfn.update_stack(update_hash)
      puts resp

      puts 'wait until complete...'
      stack_wait :stack_update_complete, {stack_name: @config[:stack_name] }
    end

    def template_url
      "https://s3-#{@config['source_region']}.amazonaws.com/#{@config['source_bucket']}/cloudformation/#{@config['project']}/#{@config['application_name']}/#{@config['version']}/master.json"
      # FIXME: make template url an actual template itself as per below
      # @config = {:version=>"99", :cloudformation_bucket=>"my_cool_bucket", :project=>"the-project", :application=>"firefly"}
      # url = "http://%{cloudformation_bucket}/cloudformation/%{project}/%{application}/%{version}/"
      # url % @config
    end

    def verbose
      STDERR
    end

    def show_events
      cfn = Aws::CloudFormation::Client.new(region: @config['region'])
      resp = cfn.describe_stack_events(stack_name: @config[:stack_name])
      resp.stack_events.reverse_each do | e |
        puts e.stack_id + ";;;" + e.event_id + ";;;" + e.stack_name + ";;;" + e.logical_resource_id #=> String
        puts e.physical_resource_id #=> String
        puts e.resource_type #=> String
        puts e.timestamp #=> Time
        puts e.resource_status #=> String, one of "CREATE_IN_PROGRESS", "CREATE_FAILED", "CREATE_COMPLETE", "DELETE_IN_PROGRESS", "DELETE_FAILED", "DELETE_COMPLETE", "DELETE_SKIPPED", "UPDATE_IN_PROGRESS", "UPDATE_FAILED", "UPDATE_COMPLETE"
        puts e.resource_status_reason #=> String
        puts e.resource_properties #=> String
      end
    end

    def stack_wait(wait, name)
      cfn = Aws::CloudFormation::Client.new(region: @config['region'])
      begin
        cfn.wait_until wait, name
      rescue
        raise "error doing #{wait} for #{name}"
      end
    end
  end
end
