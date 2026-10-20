# frozen_string_literal: true

FactoryBot.define do
  factory :taxon, class: Spree::Taxon do
    name { 'Ruby on Rails' }
    dfc_id { nil }
    name_i18n { {} }
  end
end
