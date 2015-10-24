module Spree
  class PaymentMethod::MolliePayment < PaymentMethod
    preference :api_key, :string

    def cancel(*)
      ActiveMerchant::Billing::Response.new(true, "", {}, {})
    end

    def capture(*args)
      ActiveMerchant::Billing::Response.new(true, "", {}, {})
    end

    def credit(money, credit_card, options = {})
      begin
        mollie = Mollie::API::Client.new
        mollie.setApiKey preferred_api_key

        if options[:originator].class == Spree::Refund
          original_payment = options[:originator].payment
        else
          original_payment = options[:originator]
        end

        # Retrieve the payment you want to refund from the API.
        payment = mollie.payments.get original_payment.source.transaction_id

        # Only possible to refund some methods, otherwise return dummy
        unless ['banktransfer','creditcard','ideal','mistercash',].include? payment.method
          return ActiveMerchant::Billing::Response.new(true, "Manual refund required", {}, {:authorization => '123456'})
        end

        # Refund the payment for the amount specified in the refund
        refund = mollie.payments_refunds.with(payment).create(amount: money / 100)

        return ActiveMerchant::Billing::Response.new(true, "Mollie refund called", {}, {:authorization => refund.id})

      rescue Mollie::API::Exception => e
        logger.debug "Mollie API call failed: " << (CGI.escapeHTML e.message)
        ActiveMerchant::Billing::Response.new(false, [Spree.t(:mollie_processing_error), e.message].join(' '), {}, {})
      end

    end

    def void(*args)
      ActiveMerchant::Billing::Response.new(true, "", {}, {})
    end

    def supports?(source)
      true
    end

    def source_required?
      false
    end
  end
end