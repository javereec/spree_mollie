class AddInfoToMollieCheckout < ActiveRecord::Migration
  def change
    change_table :spree_mollie_checkouts do |t|
      t.string :banktransfer_bank_name
      t.string :banktransfer_bank_account
      t.string :banktransfer_bank_bic
      t.string :banktransfer_transfer_reference
    end
  end
end
