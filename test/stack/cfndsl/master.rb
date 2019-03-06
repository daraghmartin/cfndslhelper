CloudFormation do

  # Template metadata
  AWSTemplateFormatVersion '2010-09-09'
  Description 'ciinabox ECS - Master v#{external_parameters.fetch(:version)}'

  Resource(external_parameters[:ecs_cluster_name]) {
    Type 'AWS::ECS::Cluster'
  }

end
