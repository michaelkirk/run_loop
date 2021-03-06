require 'retriable'
require 'retriable/version'

module RunLoop
  # A class to bridge the gap between retriable 1.x and 2.0.
  class RetryOpts
    def self.tries_and_interval(tries, interval, other_retry_options={})
      retriable_version = RunLoop::Version.new(Retriable::VERSION)

      if other_retry_options[:tries]
        raise RuntimeError, ':tries is not a valid key for other_retry_options'
      elsif other_retry_options[:interval]
        raise RuntimeError, ':interval is not a valid key for other_retry_options'
      elsif other_retry_options[:intervals]
        raise RuntimeError, ':intervals is not a valid key for other_retry_options'
      end

      if retriable_version >= RunLoop::Version.new('2.0.0')
        other_retry_options.merge({:intervals => Array.new(tries, interval)})
      else
        other_retry_options.merge({:tries => tries, :interval => interval})
      end
    end
  end
end

# Only in retriable 1.4.0
unless Retriable.public_instance_methods.include?(:retriable)
  require 'retriable/retry'
  module Retriable
    extend self

    def retriable(opts = {}, &block)
      raise LocalJumpError unless block_given?

      Retry.new do |r|
        r.tries    = opts[:tries] if opts[:tries]
        r.on       = opts[:on] if opts[:on]
        r.interval = opts[:interval] if opts[:interval]
        r.timeout  = opts[:timeout] if opts[:timeout]
        r.on_retry = opts[:on_retry] if opts[:on_retry]
      end.perform(&block)
    end
  end
end
