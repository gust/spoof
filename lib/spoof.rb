require 'grape'
require 'pry'

require 'resolv'
require 'unsound'
module Spoof
  module DNS
    module_function

    def resolve_mx(domain)
      Resolv::DNS.open { |dns| dns.getresources(domain, Resolv::DNS::Resource::IN::MX) }
    end
  end
end

require 'mail'
module Spoof
  module EmailValidation
    EmailValidationError = Class.new(StandardError)

    Validations = {
      local: ->(address) {
        address.local.present? ?
          Unsound::Data::Right.new(address.local) :
          Unsound::Data::Left.new(EmailValidationError.new("Address does not have a local component"))
      },
      domain: ->(address) {
        address.domain.present? ?
          Unsound::Data::Right.new(address.domain) :
          Unsound::Data::Left.new(EmailValidationError.new("Address does not have a domain component"))
      },
      mx_records: ->(address) {
        mx_records = DNS.resolve_mx(address.domain)
        mx_records.empty? ?
          Unsound::Data::Left.new(EmailValidationError.new("Could not find MX records for #{address.domain}")) :
          Unsound::Data::Right.new(mx_records)
      }
    }

    module_function

    class AccumulateSuccess
      def initialize(either, successes = [])
        @either = either
        @successes = successes
      end

      def >>(f, &blk)
        either.
          public_send(:>>, f, &blk).
          either(
            ->(_) { self },
            ->(success) { AccumulateSuccess.new(either, successes + [success]) }
          )
      end

      attr_reader :successes
      attr_reader :either
    end

    def validate(address)
      Validations.reduce(AccumulateSuccess.new(Unsound::Data::Either.of(address))) do |result, (_, validator)|
        result >> validator
      end
    end
  end
end

module Spoof
  class HttpAPI < Grape::API
    version 'v1', using: :header, vendor: 'gust'
    format :json

    resources :email_validations do
      desc "Validate an email address"
      params do
        requires :address, type: String, desc: "The email address to validate"
      end
      post do
        EmailValidation.validate(Mail::Address.new(params[:address])).tap do |result|
          binding.pry
        end
      end
    end
  end
end
