# frozen_string_literal: true

module PaymentGateways
  class TwintController < BaseController
    include OrderStockCheck
    include OrderCompletion

    protect_from_forgery except: :webhook

    before_action :load_checkout_order, only: :confirm
    before_action :check_order_cycle_expiry, only: :confirm

    def confirm
      validate_stock

      return redirect_to order_failed_route if @any_out_of_stock == true

      unless valid_payment_intent?
        processing_failed
        return redirect_to order_failed_route
      end

      unless params["redirect_status"] == "succeeded"
        processing_failed
        return redirect_to order_failed_route
      end

      complete_order
    end

    # POST /payment_gateways/twint/webhook
    # Stripe sends events here when a Twint payment changes state.
    # This covers the case where the customer closes the browser before being
    # redirected back — the front-end confirm action would never fire, but the
    # webhook still delivers confirmation.
    def webhook
      payload   = request.raw_post
      signature = request.headers["Stripe-Signature"]
      secret    = Stripe.twint_webhook_secret

      if secret.blank?
        Rails.logger.warn("TWINT_WEBHOOK_SECRET not configured, rejecting webhook")
        return render body: nil, status: :unauthorized
      end

      begin
        event = Stripe::Webhook.construct_event(payload, signature, secret)
      rescue JSON::ParserError
        return render body: nil, status: :bad_request
      rescue Stripe::SignatureVerificationError
        return render body: nil, status: :unauthorized
      end

      case event.type
      when "payment_intent.succeeded"
        handle_payment_succeeded(event.data.object)
      when "payment_intent.payment_failed"
        handle_payment_failed(event.data.object)
      end

      render body: nil, status: :ok
    end

    private

    def validate_stock
      return if sufficient_stock?

      cancel_incomplete_payments
      handle_insufficient_stock
    end

    def complete_order
      ActiveRecord::Base.transaction do
        last_payment.complete! unless last_payment.completed?
      end

      if Orders::WorkflowService.new(@order).next && @order.complete?
        processing_succeeded
        redirect_to order_completion_route
      else
        processing_failed
        redirect_to order_failed_route
      end
    rescue Spree::Core::GatewayError => e
      gateway_error(e)
      processing_failed
      redirect_to order_failed_route
    end

    def valid_payment_intent?
      Rails.logger.info("Validating payment intent: #{params['payment_intent']}")
      Rails.logger.info("Order state: #{@order.state}")
      Rails.logger.info("Last payment response code: #{last_payment&.response_code}")

      @valid_payment_intent ||= params["payment_intent"]&.starts_with?("pi_") &&
                                order_and_payment_valid?
    end

    def order_and_payment_valid?
      @order.state.in?(["payment", "confirmation"]) &&
        last_payment&.response_code == params["payment_intent"]
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

    # Called from the webhook action when Stripe confirms the payment succeeded.
    # Idempotent: safe to call more than once for the same payment intent.
    def handle_payment_succeeded(payment_intent)
      payment = Spree::Payment.find_by(response_code: payment_intent.id)
      return unless payment

      order = payment.order
      return if order.complete? # already done — nothing to do

      return unless order.state.in?(%w[payment confirmation])

      ActiveRecord::Base.transaction do
        payment.complete! unless payment.completed?
        Orders::WorkflowService.new(order).complete
      end
    rescue StandardError => e
      Rails.logger.error(
        "Twint webhook: failed to complete order #{order&.number}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      )
    end

    # Called from the webhook action when Stripe reports the payment failed.
    def handle_payment_failed(payment_intent)
      payment = Spree::Payment.find_by(response_code: payment_intent.id)
      return unless payment
      return if payment.order.complete? # can't void a completed order's payment

      payment.void! if payment.can_void?
    rescue StandardError => e
      Rails.logger.error(
        "Twint webhook: failed to void payment for intent #{payment_intent&.id}: #{e.message}"
      )
    end
  end
end
