require 'rack/test'
require 'json'

require 'spoof'

RSpec.describe "Validating an Email Address" do
  include Rack::Test::Methods

  def app
    Spoof::HttpAPI
  end

  describe "POST /email_validations" do
    context "with valid parameters" do
      def post_json(path, json_body)
        post path, JSON.dump(json_body), { 'CONTENT_TYPE' => 'application/json' }
      end

      def json_response
        JSON.load(last_response.body)
      end

      context "the email address is valid" do
        let(:json_body) do
          {
            address: "Peter Swan <pdswan@gmail.com>"
          }
        end

        it "returns a successful response" do
          post_json("/email_validations", json_body)

          expect(last_response).to be_successful

          expect(json_response["data"]).to have_key("success")
          expect(json_response["data"]["success"]["address"]).to eq({
            "format" => "Peter Swan <pdswan@gmail.com>",
            "address" => "pdswan@gmail.com",
            "local" => "pdswan",
            "domain" => "gmail.com",
            "display_name" => "Peter Swan"
          })

          expect(json_response["data"]["success"]).to have_key("results")
          expect(json_response["data"]["success"]["results"]).to include({
            "local" => "pdswan",
            "domain" => "gmail.com",
          })

          expect(json_response["data"]["success"]["results"]).
            to have_key("mx_records")

          json_response["data"]["success"]["results"]["mx_records"].each do |mx_record|
            expect(mx_record.keys).to eq ["exchange", "preference", "ttl"]
          end
        end
      end

      context "the email address is invalid" do
        let(:json_body) do
          {
            address: address
          }
        end

        describe "an address without a domain" do
          let(:address) { "whoops.farts" }

          it "returns an error response" do
            post_json("/email_validations", json_body)

            expect(last_response).to be_successful

            expect(json_response["data"]).to have_key("failure")
            expect(json_response["data"]["failure"]["address"]).to eq({
              "format" => "whoops.farts",
              "address" => "whoops.farts",
              "local" => "whoops.farts",
              "domain" => nil,
              "display_name" => nil
            })

            expect(json_response["data"]["failure"]["error"]).to eq "Address does not have a domain component"
          end
        end

        describe "an address without a local component" do
          let(:address) { "@gmail.com" }

          it "returns an error response" do
            post_json("/email_validations", json_body)

            expect(last_response).to be_successful

            expect(json_response["data"]).to have_key("failure")
            expect(json_response["data"]["failure"]["address"]).to eq({
              "format" => "@gmail.com",
              "address" => "@gmail.com",
              "local" => nil,
              "domain" => "@gmail.com",
              "display_name" => nil
            })

            expect(json_response["data"]["failure"]["error"]).to eq "Address does not have a local component"
          end
        end

        describe "a domain without mx records" do
          it "returns an error response"
        end
      end
    end

    context "with invalid parameters" do
      it "returns a 403 response"
    end
  end
end
