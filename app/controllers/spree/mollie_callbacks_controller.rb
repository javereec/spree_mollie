module Spree
  class MollieCallbacksController < Spree::BaseController
    skip_before_filter :verify_authenticity_token

    def show
      order = Order.find_by(number: params[:id]) || raise(ActiveRecord::RecordNotFound)

      mollie_payment_method = PaymentMethod.where(type: "Spree::PaymentMethod::MolliePayment").first
      payment = order.payments.valid.where(payment_method_id: mollie_payment_method.id).first

      # a payment must be present before we can continue
      (redirect_to edit_order_checkout_url(order, order.state) and return) unless mollie_payment_method && payment

      mollie = Mollie::API::Client.new
      mollie.setApiKey mollie_payment_method.preferred_api_key
      mollie_payment = mollie.payments.get(payment.source.transaction_id)

      process_payment_for_order(payment, mollie_payment, order)

      if order.completed?
        session[:order_id] = nil
        flash.notice = Spree.t(:order_processed_successfully)
        flash[:commerce_tracking] = "nothing special"
        redirect_to spree.order_path(order)
      else
        redirect_to edit_order_checkout_url(order, order.state)
      end
    end

    # Each time the payment status changes, this callback is called in background
    def update
      mollie_payment_method = PaymentMethod.where(type: "Spree::PaymentMethod::MolliePayment").first
      return unless mollie_payment_method

      if mollie_payment_method && params['id']
        begin
          mollie = Mollie::API::Client.new
          mollie.setApiKey mollie_payment_method.preferred_api_key
          mollie_payment = mollie.payments.get params['id']

          if mollie_payment
            # retrieve order via metadata mollie payment
            order = Order.find_by(number: mollie_payment.metadata.order)
            if order
              # retrieve pending payment for the order
              payment = order.payments.valid.where(payment_method_id: mollie_payment_method.id).first
              process_payment_for_order(payment, mollie_payment, order) if payment && order
            else
              logger.error "Order with reference #{mollie_payment.metadata.order} not found. Payment update not possible."
            end
          end
        rescue Mollie::API::Exception => e
          logger.debug "Mollie API call failed: " << (CGI.escapeHTML e.message)
        end
      end

      render :text => ""
    end

    private

    def process_payment_for_order(payment, mollie_payment, order)
      # wrap mollie object in ActiveMerchant Billing Repsone so we can log it
      response = ActiveMerchant::Billing::Response.new(true, mollie_payment.to_yaml, {}, {})
      payment.log_entries.create!(:details => response.to_yaml)

      payment.source.update_attributes({
        :method => mollie_payment.method,
        :status => mollie_payment.status
      })
      unless payment.completed?
        case mollie_payment.status
        when "open"
          order.next
          order.finalize!
        when "paid", "paidout" # The payment has been created, but no other status has been reached yet. The payment has been paid for. The payment has been paid for and we have transferred the sum to your bank account.
          order.update_attributes({:state => "complete", :completed_at => Time.now})
          until order.state == "complete"
            if order.next!
              order.update!
              state_callback(:after)
            end
          end
          order.finalize!

          payment.source.update_attributes({
            :paid_at => mollie_payment.paidDatetime,
          })
          payment.complete!
        when "cancelled" # Your customer has cancelled the payment.
          payment.started_processing
          payment.source.update_attributes({
            :cancelled_at => mollie_payment.cancelledDatetime,
          })
          flash.notice = Spree.t(:payment_has_been_cancelled)
          payment.failure!
        when "pending" # The payment has been started but not yet complete.
          flash.notice = Spree.t(:payment_is_pending)
          payment.pend! #may already be pending
        when "expired" # The payment has expired, for example, your customer has closed the payment screen.
          payment.started_processing
          payment.source.update_attributes({
            :expired_at => mollie_payment.expiredDatetime,
          })
          flash.notice = Spree.t(:payment_has_expired)
          payment.failure!
        else
          raise "Unexpected payment status"
        end
        payment.save # trigger updates (e.g. order)
      end
    end
  end
end