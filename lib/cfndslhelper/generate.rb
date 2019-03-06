require 'cfndsl'

module CfnDSLHelper
  class Generate
    def execute!(config)
      @config = config
      puts "generate execute"
    end

  end
end
  
