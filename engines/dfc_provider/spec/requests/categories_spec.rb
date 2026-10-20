# frozen_string_literal: true

require_relative "../swagger_helper"

RSpec.describe "Categories", swagger_doc: "dfc.yaml" do
  let(:user) { create(:oidc_user) }
  let(:Accept) { "application/json" }

  before { login_as user }

  path "/api/dfc/categories" do
    get "List categories" do
      parameter name: :Accept, in: :header, type: :string
      produces "application/json", 'application/ld+json; profile="dfc-v2"'

      response "200", "successful" do
        let!(:taxon1) { create(:taxon, id: 1, name: "Vegetables", dfc_id: "https://github.com/datafoodconsortium/taxonomies/releases/latest/download/productTypes.rdf#vegetable") }
        let!(:taxon2) { create(:taxon, id: 2, name: "Fruits", dfc_id: "https://github.com/datafoodconsortium/taxonomies/releases/latest/download/productTypes.rdf#fruit") }

        run_test! do
          expect(subject["@graph"]).to be_an(Array)
          expect(subject["@graph"].length).to eq(2)
          expect(subject["@graph"][0]["@id"]).to eq("http://test.host/api/dfc/categories/1")
          expect(subject["@graph"][0]["@type"]).to eq("skos:Concept")
          expect(subject["@graph"][0]["skos:prefLabel"]).to eq("Vegetables")
        end
      end
    end
  end

  path "/api/dfc/categories/{id}" do
    get "Show category" do
      parameter name: :id, in: :path, type: :string
      parameter name: :Accept, in: :header, type: :string
      produces "application/json", 'application/ld+json; profile="dfc-v2"'

      response "200", "successful" do
        let!(:taxon) { create(:taxon, id: 1, name: "Vegetables", description: "Fresh vegetables", dfc_id: "https://github.com/datafoodconsortium/taxonomies/releases/latest/download/productTypes.rdf#vegetable") }
        let(:id) { taxon.id }

        context "in DFC v1 format" do
          run_test! do
            expect(subject["@context"]).to eq("https://w3id.org/dfc/ontology/context/context_1.16.0.json")
            expect(subject["@id"]).to eq("http://test.host/api/dfc/categories/1")
            expect(subject["@type"]).to eq("skos:Concept")
            expect(subject["skos:prefLabel"]).to eq("Vegetables")
            expect(subject["dfc-b:description"]).to eq("Fresh vegetables")
          end
        end

        context "in DFC v2 format" do
          let(:Accept) { 'application/ld+json; profile="dfc-v2"' }

          run_test! do
            expect(subject["@context"]).to eq("https://w3id.org/dfc/ontology/context/context_2.0.0.json")
            expect(subject["@id"]).to eq("http://test.host/api/dfc/categories/1")
            expect(subject["@type"]).to eq("skos:Concept")
            expect(subject["skos:prefLabel"]).to eq("Vegetables")
            expect(subject["dfc-b:description"]).to eq("Fresh vegetables")
          end
        end
      end

      response "404", "not found" do
        let(:id) { 0 }
        run_test!
      end
    end
  end
end
