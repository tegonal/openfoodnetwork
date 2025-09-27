# frozen_string_literal: true

require 'core/gateway_error' 

module PaymentGateways
  class TwintController < BaseController
    include OrderStockCheck
    include OrderCompletion

    before_action :load_checkout_order, only: :confirm
    before_action :check_order_cycle_expiry, only: :confirm

    def confirm
      validate_stock

      # Redirect to the failure page if any items are out of stock
      redirect_to order_failed_route and return if @any_out_of_stock == true

      # Validate the payment intent
      validate_payment_intent

      # Raise an error if there are no pending payments
      raise Core::GatewayError, Spree.t(:no_pending_payments) if @order.pending_payments.empty?

      # Mark all pending payments as completed
      @order.pending_payments.each do |payment|
        payment.update_columns(state: "completed", captured_at: Time.zone.now)
      end

      # Update the order's state to complete
      @order.update_columns(payment_state: "paid",
                            shipment_state: "ready",
                            state: "complete",
                            payment_total: @order.total,
                            completed_at: Time.zone.now)

      # Redirect to the order completion route
      redirect_to order_completion_route
    end

    private

    def validate_stock
      return if sufficient_stock?

      cancel_incomplete_payments
      handle_insufficient_stock
    end

    def validate_payment_intent
      max_attempts = 30
      attempts = 0
      
      # Poll for the redirect_status to change from "pending"
      while params["redirect_status"] == "pending" && attempts < max_attempts
        Rails.logger.info("Attempt #{attempts}: redirect_status is #{params['redirect_status']}")
        sleep(1) # Wait 1 second before retrying
        attempts += 1
        params["redirect_status"] = fetch_redirect_status_from_stripe(params["payment_intent"])
        Rails.logger.info("Attempt #{attempts}: redirect_status after checking again is #{params['redirect_status']}")
      end

      # Handle timeout or invalid status
      Rails.logger.info("Good to go now as redirect status is #{params['redirect_status']}")
      if params["redirect_status"] != "succeeded" || !valid_payment_intent?
        processing_failed
        redirect_to order_failed_route and return # Redirect and stop further execution
      end
    end

    def valid_payment_intent?
      Rails.logger.info("Validating payment intent: #{params['payment_intent']}")
      Rails.logger.info("Order state: #{@order.state}")
      Rails.logger.info("Last payment response code: #{last_payment&.response_code}")

      @valid_payment_intent ||= params["payment_intent"]&.starts_with?("pi_") &&
                                order_and_payment_valid?
    end

    def order_and_payment_valid?
      valid_state = @order.state.in?(["payment", "confirmation"])
      valid_response_code = last_payment&.response_code == params["payment_intent"]

      Rails.logger.info("Order state valid: #{valid_state}")
      Rails.logger.info("Payment response code valid: #{valid_response_code}")

      valid_state && valid_response_code
    end

    def last_payment
      @last_payment ||= Orders::FindPaymentService.new(@order).last_payment
    end

    def cancel_incomplete_payments
      # The checkout could not complete due to stock running out. We void any pending (incomplete)
      # Twint payments here as the order will need to be changed and resubmitted (or abandoned).
      @order.payments.incomplete.each do |payment|
        payment.void_transaction!
        payment.adjustment&.update_columns(eligible: false, state: "finalized")
      end
      flash[:notice] = I18n.t("checkout.payment_cancelled_due_to_stock")
    end

    def fetch_redirect_status_from_stripe(payment_intent_id)
      return nil unless payment_intent_id

      begin
        # Fetch the payment intent from Stripe
        payment_intent = Stripe::PaymentIntent.retrieve(payment_intent_id)

        # Extract the redirect status from the payment intent
        payment_intent["status"] # This could be "succeeded", "requires_payment_method", "failed", etc.
      rescue Stripe::StripeError => e
        Rails.logger.error("Failed to fetch payment intent #{payment_intent_id}: #{e.message}")
        nil
      end
    end
  end
end
