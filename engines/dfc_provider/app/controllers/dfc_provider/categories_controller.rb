# frozen_string_literal: true

module DfcProvider
  class CategoriesController < DfcProvider::ApplicationController
    skip_before_action :check_authorization, only: [:index, :show]

    def index
      @categories = Spree::Taxon.all
      render_dfc(@categories.map { |t| TaxonBuilder.category(t) })
    end

    def show
      category = Spree::Taxon.find(params[:id])
      render_dfc(TaxonBuilder.category(category))
    end
  end
end
