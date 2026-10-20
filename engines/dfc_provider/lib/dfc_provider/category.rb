# frozen_string_literal: true

require "virtual_assembly/semantizer"

module DfcProvider
  class Category
    include VirtualAssembly::Semantizer::SemanticObject

    attr_accessor :dfc_id, :name, :name_i18n, :description

    SEMANTIC_TYPE = "skos:Concept"

    def initialize(semantic_id, dfc_id: nil, name: nil, name_i18n: {}, description: nil)
      @semanticPropertiesMap = {}
      @semanticId = semantic_id
      @semanticType = SEMANTIC_TYPE
      @dfc_id = dfc_id
      @name = name
      @name_i18n = name_i18n
      @description = description

      registerSemanticProperty("@id", &method(:semanticId))
      registerSemanticProperty("@type", &method(:semanticType))
      registerSemanticProperty("skos:prefLabel", &method(:name))
      registerSemanticProperty("dfc-b:dfc_id", &method(:dfc_id))
      registerSemanticProperty("dfc-b:description", &method(:description))
    end

    def semanticId
      @semanticId
    end

    def semanticType
      @semanticType
    end
  end
end
