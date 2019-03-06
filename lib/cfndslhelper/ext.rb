    def default_tags
      Property('Tags',[ {Key: 'Name', Value: Ref('EnvironmentName') }])
    end