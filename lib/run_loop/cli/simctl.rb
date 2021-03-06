require 'thor'
require 'run_loop'
require 'run_loop/cli/errors'

module RunLoop
  module CLI
    class Simctl < Thor

      attr_reader :sim_control

      desc 'tail', 'Tail the log file of the booted simulator'
      def tail
        tail_booted
      end

      no_commands do
        def tail_booted
          device = booted_device
          log_file = device.simulator_log_file_path
          exec('tail', *['-F', log_file])
        end
      end

      desc 'booted', 'Prints details about the booted simulator'
      def booted
        device = booted_device
        if device.nil?
          puts 'No simulator is booted.'
        else
          puts device
        end
      end

      no_commands do
        def sim_control
          @sim_control ||= RunLoop::SimControl.new
        end

        def booted_device
          sim_control.simulators.detect(nil) do |device|
            device.state == 'Booted'
          end
        end
      end

      desc 'install --app [OPTIONS]', 'Installs an app on a device'

      method_option 'app',
                    :desc => 'Path to a .app bundle to launch on simulator.',
                    :aliases => '-a',
                    :required => true,
                    :type => :string

      method_option 'device',
                    :desc => 'The device UDID or simulator identifier.',
                    :aliases => '-d',
                    :required => false,
                    :type => :string

      method_option 'force',
                    :desc => 'Force a re-install the existing app.',
                    :aliases => '-f',
                    :required => false,
                    :default => false,
                    :type => :boolean

      method_option 'debug',
                    :desc => 'Enable debug logging.',
                    :aliases => '-v',
                    :required => false,
                    :default => false,
                    :type => :boolean

      def install
        debug = options[:debug]

        if debug
          ENV['DEBUG'] = '1'
        end

        debug_logging = RunLoop::Environment.debug?

        device = expect_device(options)
        app = expect_app(options, device)

        bridge = RunLoop::Simctl::Bridge.new(device, app.path)

        force_reinstall = options[:force]

        before = Time.now

        if bridge.app_is_installed?
          if debug_logging
            puts "App with bundle id '#{app.bundle_identifier}' is already installed."
          end

          if force_reinstall
            if debug_logging
              puts 'Will force a re-install.'
            end
            bridge.uninstall
            bridge.install
          else
            new_digest = RunLoop::Directory.directory_digest(app.path)
            if debug_logging
              puts "      New app has SHA: '#{new_digest}'."
            end
            installed_app_bundle = bridge.fetch_app_dir
            old_digest = RunLoop::Directory.directory_digest(installed_app_bundle)
            if debug_logging
              puts "Installed app has SHA: '#{old_digest}'."
            end
            if new_digest != old_digest
              if debug_logging
                puts "Will re-install '#{app.bundle_identifier}' because the SHAs don't match."
              end
              bridge.uninstall
              bridge.install
            else
              if debug_logging
                puts "Will not re-install '#{app.bundle_identifier}' because the SHAs match."
              end
            end
          end
        else
          bridge.install
        end

        if debug_logging
          "Launching took #{Time.now-before} seconds"
          puts "Installed '#{app.bundle_identifier}' on #{device} in #{Time.now-before} seconds."
        end
      end

      no_commands do
        def expect_device(options)
          device_from_options = options[:device]
          simulators = sim_control.simulators
          if device_from_options.nil?
            default_name = RunLoop::Core.default_simulator
            device = simulators.detect do |sim|
              sim.instruments_identifier == default_name
            end

            if device.nil?
              raise RunLoop::CLI::ValidationError,
                    "Could not find a simulator with name that matches '#{device_from_options}'"
            end
          else
            device = simulators.detect do |sim|
              sim.udid == device_from_options ||
                    sim.instruments_identifier == device_from_options
            end

            if device.nil?
              raise RunLoop::CLI::ValidationError,
                    "Could not find a simulator with name or UDID that matches '#{device_from_options}'"
            end
          end
          device
        end

        def expect_app(options, device_obj)
          app_bundle_path = options[:app]
          unless File.exist?(app_bundle_path)
            raise RunLoop::CLI::ValidationError, "Expected '#{app_bundle_path}' to exist."
          end

          unless File.directory?(app_bundle_path)
            raise RunLoop::CLI::ValidationError,
                  "Expected '#{app_bundle_path}' to be a directory."
          end

          unless File.extname(app_bundle_path) == '.app'
            raise RunLoop::CLI::ValidationError,
                  "Expected '#{app_bundle_path}' to end in .app."
          end

          app = RunLoop::App.new(app_bundle_path)

          begin
            app.bundle_identifier
            app.executable_name
          rescue RuntimeError => e
            raise RunLoop::CLI::ValidationError, e.message
          end

          lipo = RunLoop::Lipo.new(app.path)
          begin
            lipo.expect_compatible_arch(device_obj)
          rescue RunLoop::IncompatibleArchitecture => e
            raise RunLoop::CLI::ValidationError, e.message
          end

          app
        end
      end
    end
  end
end
