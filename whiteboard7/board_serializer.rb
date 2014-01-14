class BoardSerializer < ActiveModel::Serializer
  #embed :ids, include: false
  attributes :id, :uid, :board_name, :board_access, :board_lock_status, :created_at
  has_many :board_members, serializer: UserNameSerializer

  def board_members
    object.users
  end
end
