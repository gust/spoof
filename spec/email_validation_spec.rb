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
      let(:json_body) do
        {
          address: "pdswan@gmail.com"
        }
      end

      def post_json(path, json_body)
        post path, JSON.dump(json_body), { 'CONTENT_TYPE' => 'application/json' }
      end

      def json_response
        JSON.load(last_response.body)
      end

      context "the email address is valid" do
        it "returns a successful response" do
          post_json("/email_validations", json_body)
          expect(json_response).to eq({
            "data" => {
              "success" => {
                "address" => "pdswan@gmail.com",
                "mx_records" => ["123.123.123"]
              }
            }
          })
        end
      end

      context "the email address is invalid" do
        describe "a domain without mx records" do
          it "returns an error response"
        end

        describe "an incorrectly formatted address" do
          it "returns an error response"
        end
      end
    end

    context "with invalid parameters" do
      it "returns a 403 response"
    end
  end
end
