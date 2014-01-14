class Board < ActiveRecord::Base
  BOARD_FOLDER = Rails.root.join("files", Rails.env, 'boards')
  BOARD_FOLDER.mkpath unless BOARD_FOLDER.exist?

  #include BoardStorage::PlainFile
  include BoardStorage::DbFile

  # Relations
  belongs_to :board_owner, class_name: 'User'
  has_many :board_users, dependent: :destroy
  has_many :users, through: :board_users, before_remove: :validate_user_remove
  has_many :board_invitations, dependent: :destroy

  # Fields
  attr_accessible :board_name, :board_access, :board_access_cd, :board_lock_status
  normalize_attributes :board_name
  as_enum :board_access, { public_board: 0, private_board: 1 }, slim: false
  as_enum :board_lock_status, { unlock: 0, lock: 1 }, slim: true
  attr_reader :canvas_objects, :canvas_options, :board_mode

  # Scopes
  scope :public_boards, -> { where board_access_cd: Board.board_accesses(:public_board) }
  scope :private_boards, -> { where board_access_cd: Board.board_accesses(:private_board) }
  scope :order_by_id, -> { order('id ASC') }

  scope :without_user, ->(user) { # all boards without user
    joins("LEFT OUTER JOIN board_users ON board_users.board_id = boards.id").
      where('(board_users.user_id IS NULL) OR (board_users.user_id != ?)', user)
  }
  scope :without_owner, -> { where(board_owner_id: nil) }

  # Delegations

  # Validations
  validates :uid, presence: true, uniqueness: true
  validates :board_access, :board_lock_status, as_enum: true

  validate do
    if board_lock_status == :lock && !board_owner
      errors[:board_lock_status] << "can't be locked without board owner"
    end
  end

  # Callbacks
  after_initialize do
    self.board_mode ||= BOARD_MODES.first
  end

  before_validation do
    # Generate unique 'uid'
    unless uid
      begin
        self.uid = SecureRandom.hex(4)
      end while self.class.exists?(uid: self.uid)
    end

    if board_owner && !users.include?(board_owner)
      users << board_owner
    end
  end

  after_create :save_canvas_params

  def validate_user_remove(user)
    if user == board_owner
      raise "Can't remove board_owner"
    end
  end

  # Boards user can join
  def self.available_boards(user = nil)
    if user
      own_boards = user.boards
      public_boards = Board.public_boards
      Board.from("(#{own_boards.to_sql} UNION #{public_boards.to_sql}) AS boards").order_by_id
    else
      Board.public_boards.order_by_id
    end
  end

  # Inactive anonymous board
  def self.expired_boards(days)
    Board.without_owner.where('updated_at <= ?', days.days.ago)
  end

  def board_title
    if board_name.present?
      board_name
    else
      "Board ##{uid}"
    end
  end

  # Board file format
  def board_mode=(mode)
    raise "Unknown mode: #{mode}" unless BOARD_MODES.include?(mode)
    @board_mode = mode
  end

  # Upload canvas object on board create
  def canvas_params=(params)
    if new_record?
      if params
        set_canvas_objects(params[:canvas_objects])

        if valid_options?(params[:canvas_options])
          @canvas_options = params[:canvas_options]
        end
      end
    else
      raise "Can't assign canvas_params"
    end
  end

  # Save canvas data after board create
  def save_canvas_params
    save_canvas_objects

    if canvas_options
      update_canvas_options(canvas_options, board_owner_id)
    end
  end

  # Handle events from board's channel
  #TODO block events from malicious user
  #
  # Returns 'false' on bad event
  def process_channel_event(event)
    user = event.connection.user
    user_id = user.try(:id)
    Rails.logger.info "*** Board#process_channel_event #{uid} #{event.name} #{user_id}"

    cmd_name = event.name.to_s
    ok = can_process_channel_command?(cmd_name, user) && process_channel_command(cmd_name, event.data, user_id)

    unless ok
      Rails.logger.error "!!! Board#process_channel_event #{uid} #{event.name} #{event.connection.id} #{user_id}"
    end

    ok
  end

  # Authorize user command
  def can_process_channel_command?(cmd_name, user = nil)
    case cmd_name
      when 'object:create', 'object:modified', 'option:change', 'board:clear'
        if board_lock_status == :lock
          user.present? && users.include?(user)
        else
          true
        end
      when 'laser:move', 'laser:flash'
        user.present? && user.package.include?('laser')
      #when 'chat:message'
      #  true
      else
        false
    end
  end

  # Execute channel command, 'cmd_data' can be updated
  def process_channel_command(cmd_name, cmd_data, user_id = nil)
    ok = true

    case cmd_name
      when 'object:create'
        obj = cmd_data['object']
        if valid_object?(obj)
          # Assign 'object_id'
          cmd_data['object_id'] = save_object(obj, user_id)
        else
          ok = false
        end

      when 'object:modified'
        obj = cmd_data['object']
        obj_id = cmd_data['object_id'].to_i

        if valid_object?(obj) && obj_id > 0
          cmd_data['object_id'] = obj_id
          ok = update_object(obj_id, obj, user_id)
        else
          ok = false
        end

      when 'option:change'
        options = cmd_data['options']
        if valid_options?(options)
          ok = update_canvas_options(options, user_id)
        else
          ok = false
        end

      when 'board:clear'
        clear_objects

      when 'laser:move', 'laser:flash'
        #TODO prevent flood

      when 'chat:message'
        #TODO prevent flood

      else
        # Block all other messages
        ok = false
    end

    ok
  end

  # File with board's objects
  def board_file
    BOARD_FOLDER + "#{id}.#{uid}.#{board_mode}"
  end

  def board_data
    str = "{\n"
    str << '"options":' << read_options_file.to_json << ",\n"
    str << '"objects":' << (read_board_file || '[]')
    str << "\n}"
    str
  end

  # Valid whiteboard options
  def valid_options?(options)
    rx_color = /^#[\da-f]{6}$/i
    options.is_a?(Hash) && options.present? && options.all? do |name, val|
      case name
        when 'background_color'
          val =~ rx_color
        else
          false
      end
    end
  end

  #TODO Send board image
  def send_to_email(sender, params)
    rx_email = /\A\s*([^@\s]{1,64})@((?:[-a-z0-9]+\.)+[a-z]{2,})\s*\z/i
    unless params[:email] =~ rx_email
      raise 'Invalid email'
    end

    unless params[:image_name].present?
      raise "No image name"
    end

    unless params[:image_blob].instance_of? ActionDispatch::Http::UploadedFile
      raise "No image file"
    end

    UserMailer.whiteboard(self, sender, params[:email], params[:image_name], params[:image_blob]).deliver!
  end
end
