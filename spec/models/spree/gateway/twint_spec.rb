# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Spree::Gateway::Twint do
  let(:order) { create(:order_ready_for_payment) }
  let(:payment_method) { described_class.new }

  describe "#external_gateway?" do
    it "returns true" do
      expect(payment_method.external_gateway?).to eq true
    end
  end

  describe "#method_type" do
    it "returns 'twint'" do
      expect(payment_method.method_type).to eq 'twint'
    end
  end

  describe "#provider_class" do
    it "returns the correct provider class" do
      expect(payment_method.provider_class).to eq(
        ActiveMerchant::Billing::StripePaymentIntentsGateway
      )
    end
  end

  describe "#payment_profiles_supported?" do
    it "returns false" do
      expect(payment_method.payment_profiles_supported?).to eq false
    end
  end

  describe "#source_required?" do
    it "returns false" do
      expect(payment_method.source_required?).to eq false
    end
  end

  describe "#stripe_account_id" do
    let(:stripe_account) { create(:stripe_account, stripe_user_id: "acct_123") }

    before do
      allow(StripeAccount).to receive(:find_by).and_return(stripe_account)
      payment_method.preferred_enterprise_id = 1
    end

    it "returns the Stripe account ID" do
      expect(payment_method.stripe_account_id).to eq "acct_123"
    end
  end

  describe "#external_payment_url" do
    let(:twint_client_secret) { "twint_client_secret" }
    let(:confirm_payment) {
      double(
        "Stripe::PaymentIntent",
        id: "pi_123",
        next_action: double(
          redirect_to_url: double(
            url: "http://twint-test.org"
          )
        )
      )
    }

    before do
      allow(payment_method).to receive(:create_twint_payment_intent).and_return(twint_client_secret)
      allow(payment_method).to receive(:confirm_payment)
        .with(twint_client_secret)
        .and_return(confirm_payment)
      allow(order).to receive_message_chain(:pending_payments, :last, :update)
    end

    it "returns the Twint redirect URL" do
      expect(payment_method.external_payment_url(order:)).to eq "http://twint-test.org"
    end
  end

  describe "#options" do
    before do
      allow(payment_method).to receive(:stripe_account_id).and_return("acct_123")
      allow(Stripe).to receive(:api_key).and_return("sk_test_123")
    end

    it "returns options with Stripe account and API key" do
      options = payment_method.options
      expect(options[:stripe_account]).to eq "acct_123"
      expect(options[:login]).to eq "sk_test_123"
    end
  end

  describe "#confirm_payment" do
    let(:payment_intent_id) { "pi_123" }

    before do
      payment_method.instance_variable_set(:@order, order) # Ensure @order is set
      allow(Stripe::PaymentIntent).to receive(:confirm).and_return(
        double("Stripe::PaymentIntent", id: payment_intent_id)
      )
      allow(payment_method).to receive(:payment_gateways_confirm_twint_url)
        .and_return("http://example.com/confirm_twint")
    end

    it "confirms the payment intent" do
      result = payment_method.confirm_payment(payment_intent_id)
      expect(result.id).to eq payment_intent_id
    end
  end

  describe "#void" do
    let(:stripe_account_id) { "acct_123" }
    let(:gateway_options) { { currency: "CHF", order_id: order.number } }
    let(:provider) { instance_double(ActiveMerchant::Billing::StripePaymentIntentsGateway) }

    before do
      allow(payment_method).to receive(:stripe_account_id).and_return(stripe_account_id)
      allow(payment_method).to receive(:provider).and_return(provider)
    end

    context "when the payment intent is in a voidable state" do
      before do
        allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(
          double("PaymentIntent", status: "requires_capture", amount_received: 220)
        )
      end

      it "cancels the payment intent via provider.void" do
        expect(provider).to receive(:void).with("pi_123", hash_including(stripe_account: stripe_account_id))
        payment_method.void("pi_123", gateway_options)
      end
    end

    context "when the payment intent has already been captured" do
      before do
        allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(
          double("PaymentIntent", status: "succeeded", amount_received: 220)
        )
      end

      it "refunds the full amount via provider.refund" do
        expect(provider).to receive(:refund).with(220, "pi_123", hash_including(stripe_account: stripe_account_id))
        payment_method.void("pi_123", gateway_options)
      end
    end

    context "when Stripe raises an error" do
      before do
        allow(Stripe::PaymentIntent).to receive(:retrieve).and_raise(Stripe::StripeError.new("error"))
      end

      it "returns a failed ActiveMerchant response" do
        result = payment_method.void("pi_123", gateway_options)
        expect(result.success?).to eq false
      end
    end
  end

  describe "#credit" do
    let(:stripe_account_id) { "acct_123" }
    let(:gateway_options) { { currency: "CHF", order_id: order.number } }
    let(:provider) { instance_double(ActiveMerchant::Billing::StripePaymentIntentsGateway) }

    before do
      allow(payment_method).to receive(:stripe_account_id).and_return(stripe_account_id)
      allow(payment_method).to receive(:provider).and_return(provider)
    end

    it "issues a partial refund via provider.refund" do
      expect(provider).to receive(:refund).with(110, "pi_123", hash_including(stripe_account: stripe_account_id))
      payment_method.credit(110, "pi_123", gateway_options)
    end

    context "when Stripe raises an error" do
      before do
        allow(provider).to receive(:refund).and_raise(Stripe::StripeError.new("error"))
      end

      it "returns a failed ActiveMerchant response" do
        result = payment_method.credit(110, "pi_123", gateway_options)
        expect(result.success?).to eq false
      end
    end
  end

  describe "#handle_stripe_error" do
    let(:error) { Stripe::StripeError.new("An error occurred") }

    it "returns an ActiveMerchant::Billing::Response with the error message" do
      response = payment_method.handle_stripe_error(error)
      expect(response.success?).to eq false
      expect(response.message).to eq "An error occurred"
    end
  end

  describe "#ensure_enterprise_selected" do
    context "when preferred enterprise ID is not set" do
      before { payment_method.preferred_enterprise_id = nil }

      it "adds an error to the payment method" do
        payment_method.ensure_enterprise_selected
        expect(payment_method.errors[:stripe_account_owner]).to include(I18n.t(:error_required))
      end
    end

    context "when preferred enterprise ID is set" do
      before { payment_method.preferred_enterprise_id = 1 }

      it "does not add any errors" do
        payment_method.ensure_enterprise_selected
        expect(payment_method.errors[:stripe_account_owner]).to be_empty
      end
    end
  end

  describe "#create_twint_payment_intent" do
    let(:stripe_account_id) { "acct_123" }

    before do
      payment_method.instance_variable_set(:@order, order) # Ensure @order is set
      allow(payment_method).to receive(:stripe_account_id).and_return(stripe_account_id)
    end

    it "creates a Twint payment intent" do
      payment_intent = double(
        "Stripe::PaymentIntent",
        id: "pi_123"
      )
      allow(Stripe::PaymentIntent).to receive(:create).and_return(payment_intent)

      result = payment_method.create_twint_payment_intent
      expect(result).to eq "pi_123"
    end

    it "handles Stripe errors gracefully" do
      allow(Stripe::PaymentIntent).to receive(:create).and_raise(
        Stripe::StripeError.new("An error occurred")
      )

      response = payment_method.create_twint_payment_intent
      expect(response.success?).to eq false
    end
  end
end
