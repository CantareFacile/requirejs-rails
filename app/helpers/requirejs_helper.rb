require 'requirejs/error'

module RequirejsHelper
  # EXPERIMENTAL: Additional priority settings appended to
  # any user-specified priority setting by requirejs_include_tag.
  # Used for JS test suite integration.
  mattr_accessor :_priority
  @@_priority = []

  def _requirejs_data(name, &block)
    {}.tap do |data|
      if name
        name += ".js" unless name =~ /\.js$/
        data['main'] = _javascript_path(name).
                        sub(/\.js$/,'').
                        sub(base_url(name), '').
                        sub(/\A\//, '')
      end

      data.merge!(yield controller) if block_given?
    end.map do |k, v|
      %Q{data-#{k}="#{v}"}
    end.join(" ")
  end

  def _requirejs_data_main(name)
    if name
      name += ".js" unless name =~ /\.js$/
      _javascript_path(name).
          sub(/\.js$/,'').
          sub(base_url(name), '').
          sub(/\A\//, '')
    end
  end

  def requirejs_include_tag(name = nil, options = {}, &block)
    requirejs = Rails.application.config.requirejs

    if requirejs.loader == :almond
      name = requirejs.module_name_for(requirejs.build_config['modules'][0])
      return _almond_include_tag(name, &block)
    end

    _once_guard do
      html = ActiveSupport::SafeBuffer.new
      html.safe_concat "<script>#{requirejs_config_js(name)}</script>\n" unless options[:skip_config]
      html.safe_concat %Q|<script #{_requirejs_data(name, &block)} src="#{_javascript_path requirejs.bootstrap_file}" data-turbolinks-track></script>|
      html
    end
  end

  def requirejs_config_js(name = nil, with: [], config: {})
    requirejs = Rails.application.config.requirejs

    unless requirejs.run_config.empty?
      run_config = requirejs.run_config.dup
      unless _priority.empty?
        run_config = run_config.dup
        run_config[:priority] ||= []
        run_config[:priority].concat _priority
      end
      current_base_url = base_url(name)
      if Rails.application.config.assets.digest

        # Generate digestified paths from the modules spec
        paths = {}
        with = *with
        requirejs.build_config['modules'].each do |m|
          module_name = requirejs.module_name_for m
          if m['private']
            next unless with.include?(module_name)
          end
          paths[module_name] = _javascript_path(module_name).sub(/\.js$/, '').sub("#{current_base_url}/", '')
        end

        if run_config.has_key? 'paths'
          # Add paths for assets specified by full URL (on a CDN)
          run_config['paths'].each { |k,v| paths[k] = v if v =~ %r{\A(https?:|//)} }
        end

        # Override user paths, whose mappings are only relevant in dev mode
        # and in the build_config.
        run_config['paths'] = paths
      end
      run_config['config'] ||= {}
      run_config['config'].merge! config

      run_config['baseUrl'] = current_base_url
      main_config = {
        '_src' => _javascript_path(requirejs.bootstrap_file),
        '_main' => _requirejs_data_main(name)
      }
      run_config.merge! main_config
      "var require=#{run_config.to_json};".html_safe
    end
  end

  def _once_guard
    if defined?(controller) && controller.requirejs_included
      raise Requirejs::MultipleIncludeError, "Only one requirejs_include_tag allowed per page."
    end

    retval = yield

    controller.requirejs_included = true if defined?(controller)
    retval
  end

  def _almond_include_tag(name, &block)
    "<script src='#{_javascript_path name}'></script>\n".html_safe
  end

  def _javascript_path(name)
    if defined?(javascript_path)
      javascript_path(name)
    else
      "/assets/#{name}"
    end
  end

  def base_url(js_asset)
    js_asset_path = javascript_path(js_asset)
    uri = URI.parse(js_asset_path)
    asset_host = uri.host && js_asset_path.sub(uri.path, '')
    [asset_host, Rails.application.config.assets.prefix].join
  end
end
