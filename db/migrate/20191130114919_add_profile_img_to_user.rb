class AddProfileImgToUser < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :profile_img, :string
  end
end
