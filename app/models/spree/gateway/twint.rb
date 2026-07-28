# frozen_string_literal: true

module Spree
  class Gateway
    class Twint < Gateway
      include Rails.application.routes.url_helpers
      preference :enterprise_id, :integer

      VOIDABLE_STATES = [
        "requires_payment_method", "requires_capture", "requires_confirmation", "requires_action"
      ].freeze

      validate :ensure_enterprise_selected

      def external_gateway?
        true
      end

      def method_type
        'twint'
      end

      def provider_class
        ActiveMerchant::Billing::StripePaymentIntentsGateway
      end

      def payment_profiles_supported?
        false
      end

      def source_required?
        false
      end

      def stripe_account_id
        StripeAccount.find_by(enterprise_id: preferred_enterprise_id)&.stripe_user_id
      end

      def external_payment_url(options)
        @order = options[:order]
        @twint_client_secret = create_twint_payment_intent
        @confirm_payment = confirm_payment(@twint_client_secret)
        @order.pending_payments.last.update(response_code: @confirm_payment.id)
        @confirm_payment.next_action.redirect_to_url.url
      end

      def options
        options = super
        options[:stripe_account] = stripe_account_id
        options.merge(login: Stripe.api_key)
      end

      def confirm_payment(payment_intent_id)
        Rails.logger.info("Executing Twint purchase method for PaymentIntent: #{payment_intent_id}")
        Rails.logger.info("Twint PaymentIntent confirmation will use Stripe account: #{stripe_account_id}")
        Stripe::PaymentIntent.confirm(
          payment_intent_id,
          {
            return_url: payment_gateways_confirm_twint_url(order_id: @order.number,
                                                           order_token: @order.token),
            payment_method_data: { type: 'twint' }
          }, {
            stripe_account: stripe_account_id
          }
        )
      end

      # NOTE: this method is required by Spree::Payment::Processing
      # If the PaymentIntent is still in a cancellable state, cancel it.
      # If it has already been confirmed/captured, issue a full refund instead.
      def void(payment_intent_id, gateway_options)
        payment_intent_response = Stripe::PaymentIntent.retrieve(
          payment_intent_id, { stripe_account: stripe_account_id }
        )
        gateway_options[:stripe_account] = stripe_account_id

        if voidable?(payment_intent_response)
          provider.void(payment_intent_id, gateway_options)
        else
          provider.refund(
            payment_intent_response.amount_received, payment_intent_id, gateway_options
          )
        end
      rescue Stripe::StripeError => e
        handle_stripe_error(e)
      end

      # NOTE: this method is required by Spree::Payment::Processing
      def credit(money, payment_intent_id, gateway_options)
        gateway_options[:stripe_account] = stripe_account_id
        provider.refund(money, payment_intent_id, gateway_options)
      rescue Stripe::StripeError => e
        handle_stripe_error(e)
      end

      def handle_stripe_error(error)
        ActiveMerchant::Billing::Response.new(false, error.message)
      end

      def ensure_enterprise_selected
        return if preferred_enterprise_id&.positive?

        errors.add(:stripe_account_owner, I18n.t(:error_required))
      end

      # This method is only used for Twint payment method
      def create_twint_payment_intent
        Rails.logger.info("Twint PaymentIntent will use Stripe account: #{stripe_account_id}")
        if @order.total < 1
          raise Core::GatewayError, I18n.t('spree.twint.minimum_amount_error', amount: '1 CHF')
        end

        payment_intent = Stripe::PaymentIntent.create(
          {
            amount: (@order.total * 100).to_i,
            currency: 'chf',
            payment_method_types: ['twint'],
            description: "Order ##{@order.number} - #{@order.email} - #{@order.bill_address&.firstname} #{@order.bill_address&.lastname}"
          },
          {
            stripe_account: stripe_account_id
          }
        )
        payment_intent.id
      rescue Stripe::StripeError => e
        handle_stripe_error(e)
      end

      private

      def voidable?(payment_intent_response)
        VOIDABLE_STATES.include?(payment_intent_response.status)
      end
    end
  end
end
