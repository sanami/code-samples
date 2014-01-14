# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :board do
    sequence(:board_name) {|n| "Board #{n}" }
    board_access :public_board
    board_lock_status :unlock

    trait :with_owner do
      board_owner { create :user }
    end
  end
end
