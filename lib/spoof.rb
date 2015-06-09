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

    module Results
      class Success
        include Concord::Public.new(:address, :results)
      end

      class Failure
        include Concord::Public.new(:address, :error)
      end
    end

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

    def validate(address_string)
      Unsound::Control.try {
        Mail::Address.new(address_string)
      }.and_then { |address|
        Unsound::Control.try {
          Validations.reduce({ }) do |result, (validator_name, validator)|
            validator[address].either(
              ->(exception) { raise exception },
              ->(success) { result.merge(validator_name => success) }
            )
          end
        }.either(
          ->(error) { Results::Failure.new(address, error) },
          ->(results) { Results::Success.new(address, results) }
        )
      }.or_else { |error|
        Results::Failure.new(nil, error)
      }
    end

  end
end

class Serializer
  def initialize
    @registry = { }
  end

  def register(serializes, serializer)
    registry.merge!(serializes => serializer)
  end

  def serialize(object)
    case object
    when Hash
      object.reduce({ }) do |serialized, (key, value)|
        serialized.merge(key => serialize(value))
      end
    when Array
      object.map { |i| serialize(i) }
    else
      if serializer = find_serializer(object)
        serialize(serializer.call(object))
      else
        object
      end
    end
  end

  private

  attr_reader :registry

  def find_serializer(object)
    return unless key = registry.keys.find { |serializes| serializes[object] }
    registry[key]
  end
end

module Spoof
  JsonSerializer = Serializer.new.tap do |serializer|
    serializer.register(
      ->(object) { object.is_a?(EmailValidation::Results::Success) },
      ->(object) do
        {
          success: {
            address: object.address,
            results: object.results
          }
        }
      end
    )
    serializer.register(
      ->(object) { object.is_a?(EmailValidation::Results::Failure) },
      ->(object) do
        {
          failure: {
            address: object.address,
            error: object.error
          }
        }
      end
    )
    serializer.register(
      ->(object) { object.is_a?(Mail::Address) },
      ->(object) do
        {
          format: object.format,
          address: object.address,
          local: object.local,
          domain: object.domain,
          display_name: object.display_name
        }
      end
    )
    serializer.register(
      ->(object) { object.is_a?(Resolv::DNS::Resource::IN::MX) },
      ->(object) do
        {
          exchange: object.exchange,
          preference: object.preference,
          ttl: object.ttl
        }
      end
    )
  end

  class HttpAPI < Grape::API
    version 'v1', using: :header, vendor: 'gust'
    format :json

    resources :email_validations do
      desc "Validate an email address"
      params do
        requires :address, type: String, desc: "The email address to validate"
      end
      post do
        { data: JsonSerializer.serialize(EmailValidation.validate(params[:address])) }
      end
    end
  end
end
