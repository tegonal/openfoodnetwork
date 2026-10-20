# frozen_string_literal: true

class TaxonBuilder < DfcBuilder
  def self.semantic_id(taxon)
    urls.category_url(id: taxon.id)
  end

  def self.category(taxon)
    DfcProvider::Category.new(
      semantic_id(taxon),
      dfc_id: taxon.dfc_id,
      name: taxon.name,
      name_i18n: taxon.name_i18n,
      description: taxon.description,
    )
  end

  def self.apply(dfc_category, spree_taxon)
    spree_taxon.name = dfc_category.name if dfc_category.name.present?
    spree_taxon.name_i18n = dfc_category.name_i18n if dfc_category.name_i18n.present?
    spree_taxon.description = dfc_category.description if dfc_category.description.present?
    spree_taxon.dfc_id = dfc_category.dfc_id if dfc_category.dfc_id.present?
  end
end
