class CreateSpreeMollieCheckouts < ActiveRecord::Migration
  def change
    create_table :spree_mollie_checkouts do |t|
      t.string   :transaction_id
      t.string   :mode
      t.string   :status
      t.float    :amount
      t.string   :description
      t.string   :method
      t.datetime :created_at
      t.datetime :paid_at
      t.datetime :cancelled_at
      t.datetime :expired_at
      t.float    :amount_refunded
      t.float    :amount_remaining
      t.datetime :refunded_at
    end
  end
end
