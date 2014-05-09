module Spree
  class MollieCallbacksController < Spree::BaseController
    skip_before_filter :verify_authenticity_token

    def show
      order = Order.find_by(number: params[:id]) || raise(ActiveRecord::RecordNotFound)
                
      mollie_payment_method = PaymentMethod.where(type: "Spree::PaymentMethod::MolliePayment").first
      payment = order.payments.pending.where(payment_method_id: mollie_payment_method.id).first
      
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
            # retrieve pending payment for the order
            payment = order.payments.pending.where(payment_method_id: mollie_payment_method.id).first
            process_payment_for_order(payment, mollie_payment, order) if payment && order
          end
        rescue Mollie::API::Exception => e
          logger.debug << "Mollie API call failed: " << (CGI.escapeHTML e.message)
        end
      end

      render :text => ""
    end

    private 

    def process_payment_for_order(payment, mollie_payment, order)
      payment.started_processing!
      
      payment.source.update_attributes({
        :method => mollie_payment.method,
        :status => mollie_payment.status
      })
      unless payment.completed?
        case mollie_payment.status
        when "open"
          payment.pend #may already be pending
        when "paid", "paidout"
          payment.source.update_attributes({
            :paid_at => mollie_payment.paidDatetime,
          })
          payment.complete!
          order.update_attributes({:state => "complete", :completed_at => Time.now})
          order.finalize!
          order.updater.update
        when "cancelled"
          payment.source.update_attributes({
            :cancelled_at => mollie_payment.cancelledDatetime,
          })
          flash.notice = Spree.t(:payment_has_been_cancelled)
          payment.failure!
        when "expired"
          payment.source.update_attributes({
            :expired_at => mollie_payment.expiredDatetime,
          })
          flash.notice = Spree.t(:payment_has_expired)
          payment.failure!
        else
          raise "Unexpected payment status"
        end
      end
    end
  end
end