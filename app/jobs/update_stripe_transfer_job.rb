class UpdateStripeTransferJob < ApplicationJob
  queue_as :default

  # payment_intent_id: String, order_id: Integer, tries: Integer
  def perform(payment_intent_id, order_id, tries = 0)
    order = Spree::Order.find_by(id: order_id)
    return unless payment_intent_id && order

    Rails.logger.info("[Twint][UpdateStripeTransferJob] perform called for PI=#{payment_intent_id} order_id=#{order_id})")

    begin
      max_attempts = 6
      attempt = 0
      transfer_id = nil

      while attempt < max_attempts && transfer_id.blank?
        pi = Stripe::PaymentIntent.retrieve(payment_intent_id)

        charge = if pi.respond_to?(:charges) && pi.charges.respond_to?(:data) && pi.charges.data.present?
                   pi.charges.data.first
                 else
                   Stripe::Charge.list(payment_intent: payment_intent_id, limit: 1).data.first
                 end

        transfer_id = charge&.transfer

        break if transfer_id.present?

        attempt += 1
        wait = 5
        Rails.logger.info("[Twint][UpdateStripeTransferJob] No transfer yet for PI #{payment_intent_id}; attempt #{attempt}/#{max_attempts}, waiting #{wait}s")
        sleep(wait)
      end

      if transfer_id.present?
        description = "Order ##{order.number} - #{order.email}"
        metadata = { order_number: order.number, customer_email: order.email }

        Stripe::Charge.update(charge.id, { description: description, metadata: metadata }) if charge
        Stripe::Transfer.update(transfer_id, { description: description, metadata: metadata })

        Rails.logger.info("[Twint][UpdateStripeTransferJob] Updated transfer #{transfer_id} for PI #{payment_intent_id}")
      else
        Rails.logger.warn("[Twint][UpdateStripeTransferJob] Giving up updating transfer for PI #{payment_intent_id} after #{max_attempts} attempts")
      end
    rescue Stripe::StripeError => e
      Rails.logger.error("[Twint][UpdateStripeTransferJob] Stripe error: #{e.message}")
      raise
    rescue StandardError => e
      Rails.logger.error("[Twint][UpdateStripeTransferJob] Unexpected error: #{e.message}")
      raise
    end
  end
end
