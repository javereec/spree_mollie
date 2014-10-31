module Spree
  CheckoutController.class_eval do
    before_filter :redirect_to_mollie, :only => [:update]

    private

    def redirect_to_mollie
      return if @order.completed? || @order.outstanding_balance == 0
      return unless params[:state] == "payment"

      # check to see if there is an existing mollie payment pending
      mollie_payment_method = PaymentMethod.find_by(type: 'Spree::PaymentMethod::MolliePayment')
      payment = @order.payments.valid.where(payment_method: mollie_payment_method).first

      begin
        mollie = Mollie::API::Client.new
        mollie.setApiKey mollie_payment_method.preferred_api_key
        mollie_payment = mollie.payments.get(payment.source.transaction_id) if payment

        unless payment && mollie_payment && ['open','pending'].include?(mollie_payment.status)
          mollie_payment = mollie.payments.create \
            :amount       => @order.total,
            :description  => "Payment for order #{@order.number}",
            :redirectUrl  => mollie_url(@order, :utm_nooverride => 1), # ensure that transactions are credited to the original traffic source
            :method       => params[:order][:payments_attributes][0][:payment_method_id],
            :metadata     => {
              :order => @order.number
            }

          # Create mollie payment
          payment = @order.payments.create!({
            :source => Spree::MollieCheckout.create({
                :transaction_id => mollie_payment.id,
                :mode => mollie_payment.mode,
                :status => mollie_payment.status,
                :amount => mollie_payment.amount,
                :description => mollie_payment.description,
                :created_at => mollie_payment.createdDatetime
              }),
            :amount => @order.total,
            :payment_method => mollie_payment_method
          })
          # payment.pend!
        end

        redirect_to mollie_payment.getPaymentUrl and return
      rescue Mollie::API::Exception => e
        logger.debug << "Mollie API call failed: " << (CGI.escapeHTML e.message)
      end
    end
  end
end