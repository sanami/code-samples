require 'face_morphing'

class UserDetail < ActiveRecord::Base
  RACES = ['white', 'black', 'asian', 'hispanic', 'middle eastern', 'indian'].freeze
  GENDERS = ['male', 'female'].freeze

  # Relations
  belongs_to :user
  has_many :courses, through: :users_course
  has_many :morphed_photos, dependent: :destroy
  mount_uploader :user_photo, UserPhotoUploader
  mount_uploader :detected_user_photo, UserPhotoUploader
  mount_uploader :cropped_user_photo, UserPhotoUploader
  mount_uploader :mask_photo, UserPhotoUploader

  # Fields
  as_enum :main_photo_status, { pending: 0, accepted: 1, rejected: 2, removed: 3 }, dirty: true
  serialize :user_data, ActiveRecord::Coders::Hstore
  attr_accessible :gender, :race, :race_map, :multi_race_map

  # Scopes
  scope :with_status, ->(status) { where('main_photo_status_cd = ?', UserDetail.main_photo_statuses(status)) }
  scope :with_uploaded_photo, -> { where('user_photo IS NOT NULL') }

  # Delegations
  delegate :email, :name, to: :user, prefix: true, allow_nil: false
  delegate :org_name, to: :user, prefix: false, allow_nil: false

  # Validations
  validates_inclusion_of :race, in: RACES, allow_nil: true
  validates_inclusion_of :gender, in: GENDERS, allow_nil: true

  # Filters
  before_validation do
    if main_photo_status_changed?
      if main_photo_status == :removed
        self.registration_state = :require_photo
        remove_cropped_user_photo!
        remove_user_photo!
        morphed_photos.destroy_all
      end
    end

    if user_photo_changed? || cropped_user_photo_changed?
      unless cropped_user_photo.present?
        reset_crop_params
      end
    end
  end

  # States
  state_machine :registration_state, initial: :require_name do
    state :require_name
    state :require_photo
    state :registration_complete

    event :apply_student_name do
      transition :require_name => :require_photo, if: ->(user_detail) do
        user_detail.user_info_full?
      end
    end

    event :apply_student_photo do
      transition :require_photo => :registration_complete, if: ->(user_detail) do
        user_detail.user_photo.present? && user_detail.detected_user_photo.present?
      end
    end
  end

  # Callbacks
  before_create do
    begin
      self.id = SecureRandom.random_number(1_000_000_000)
    end while UserDetail.where(:id => self.id).exists?
  end

  def self.filter(params)
    all = self

    if params[:email].present?
      all = all.joins(:user).where('LOWER(users.email) LIKE ?', "%#{params[:email].downcase}%")
    end

    if params[:name].present?
      name = "%#{params[:name].downcase}%"
      all = all.joins(:user).where('(LOWER(users.first_name) LIKE ?) OR (LOWER(users.last_name) LIKE ?)', name, name)
    end

    if params[:org].present?
      all = all.joins(:user).where('users.org_id = ?', params[:org])
    end

    if params[:status].present?
      all = all.where('main_photo_status_cd = ?', UserDetail.main_photo_statuses(params[:status]))
    end

    all = all.order('main_photo_status_cd ASC, created_at DESC')

    all
  end

  def self.race_for_select
    @@race_for_select ||= RACES.inject({}) {|memo, obj| memo[obj.titleize] = obj; memo}
  end

  def self.race_map_for_select
    @@race_map_for_select ||= FACE_CONFIG['race_identifiers'].keys
  end

  def user_info_full?
    user.valid?(:check_names) && gender.present? && race.present?
  end

  def gender
    user_data['gender']
  end

  def gender=(g)
    user_data['gender'] = g
  end

  def female?
    gender == 'female'
  end

  def male?
    gender == 'male'
  end

  # Race identifier
  def race
    user_data['race']
  end

  def race=(r)
    user_data['race'] = r
    user_data['race_map'] = FACE_CONFIG['race_identifiers'].key(r)
  end

  # Race label
  def race_map
    user_data['race_map']
  end

  def race_map=(r)
    if FACE_CONFIG['race_identifiers'].include? r
      user_data['race_map'] = r
      user_data['race'] = FACE_CONFIG['race_identifiers'][r]
    end
  end

  # Multiple race labels
  def multi_race_map
    if user_data['multi_race_map'].present?
      user_data['multi_race_map'].split(',')
    elsif user_data['race_map'].present?
      [ user_data['race_map'] ]
    else
      []
    end
  end

  # Assign array ["", "Black", "White"]
  def multi_race_map=(params)
    races = params.uniq.select do |race|
      FACE_CONFIG['race_weights'].include? race
    end

    user_data['multi_race_map'] = races.join(',')

    primary_race = races.max do |a, b|
      FACE_CONFIG['race_weights'][a] <=> FACE_CONFIG['race_weights'][b]
    end

    self.race = FACE_CONFIG['race_identifiers'][primary_race]
  end

  # Current crop values
  def crop_params
    user_data['crop']
  end

  def reset_crop_params
    user_data.delete 'crop'
  end

  # Photo used for processing: original or cropped
  def student_photo
    if cropped_user_photo.present?
      cropped_user_photo
    else
      user_photo
    end
  end

  def student_photo_cropped?
    cropped_user_photo.present?
  end

  # Update details
  def update_details(params)
    if params[:main_photo_status].present?
      self.main_photo_status = params[:main_photo_status]
    end

    if accepted?
      user_data['gender'] = params[:gender]
      if params[:race].present?
        self.race = params[:race]
      elsif params[:race_map].present?
        self.race_map = params[:race_map]
      end

      user.email = params[:email]
      if params[:org].present?
        user.org = Org.find params[:org]
      else
        user.org = nil
      end

      user.save!
    end
    save!
  end

  # Start job
  def run_morphing
    morph_time = Time.now.to_i.to_s
    user_data['morph_time'] = morph_time
    save
    Delayed::Job.enqueue GenerateMorphsJob.new(id, morph_time)
  end

  # Generate morphed photo for each race
  def generate_morphed_photo_set(params)
    if race && gender
      RACES.each do |race|
        next if params[:skip_own_race] && race == self.race

        morphed_photo = morphed_photos.with_race(race).first
        unless morphed_photo
          morphed_photo = morphed_photos.build race_mask: race
        end

        morphed_photo.generate_photo params[:data_f], params[:data_t]
      end
    else
      raise "Race/gender not set" unless params[:no_error]
    end
  end

  # Regenerate specific morphed photo
  def update_morphed_photo(params)
    morphed_photo = morphed_photos.find(params[:morphed_photo_id])
    morphed_photo.generate_photo(params[:data_f], params[:data_t])
  end

  # Params from ":id?mask=Asian&F=65&T=50&cache=no" and ":id?tag=Bla"
  def get_morphed_photo(params)
    morphed_photo = nil

    if student_photo.blank?
      raise "Photo not uploaded"
    end

    if params[:tag].present?
      # Search by tag
      morphed_photo = morphed_photos.with_tags(params[:tag]).first
      unless morphed_photo
        raise "Photo not found: #{params[:tag]}"
      end

    else
      race = params[:mask].try :downcase
      unless RACES.include? race
        raise "Unknown mask: #{race}"
      end

      unless params[:F] && params[:T]
        raise "F/T params required"
      end

      f = params[:F].to_i
      t = params[:T].to_i

      morphed_photo = morphed_photos.with_race(race).first
      unless morphed_photo
        morphed_photo = morphed_photos.build race_mask: race
      end

      if params[:cache] == 'no' || f != morphed_photo.data_f || t != morphed_photo.data_t
        morphed_photo.generate_photo(f, t)
      end
    end

    morphed_photo.try(:photo)
  end

  # Assign/upload photo for student user
  #
  # Returns 'true' if photo passed detection
  def upload_user_photo(user_photo)
    tool = FaceMorphing.new

    # Fix rotation based on EXIF
    photo_path = tool.auto_oriented(user_photo.path)

    # Call detecting script, set 'detected_path' to new file
    detected_path = tool.detected(photo_path)
    if detected_path
      # Only if detection succeed
      self.user_photo = File.open(photo_path)
      self.detected_user_photo = File.open(detected_path)

      # Resize to max width for morphed images
      resized_path = tool.cropped(photo_path)
      if resized_path
        self.cropped_user_photo = File.open(resized_path)
        reset_crop_params
      end

      apply_student_photo
      save
    else
      false
    end
  rescue => ex
    false
  end

  # Detected from uploaded photo
  def generate_detected_user_photo
    # 'user_photo' file path on filesystem
    image_path = student_photo.current_path

    # Call detecting script, set 'image_path' to new file
    tool = FaceMorphing.new
    image_path = tool.detected(image_path)
    if image_path
      self.detected_user_photo = File.open(image_path)
    else
      self.remove_detected_user_photo!
    end
  end

  # Params { :number => 1..3 }
  def get_shuffle(params)
    if student_photo.blank?
      raise "Photo not uploaded"
    end

    shuffles = FACE_CONFIG['race_shuffles'][race]
    raise "Race not set" unless shuffles

    shuffle_race = shuffles[params[:number].to_i]
    raise "Wrong shuffle number" unless shuffle_race

    # MorphedPhoto
    morphed_photo = morphed_photos.with_race(shuffle_race).first
    unless morphed_photo
      morphed_photo = morphed_photos.build race_mask: shuffle_race
    end

    # Image file
    unless morphed_photo.photo.present?
      morphed_photo.generate_photo(FACE_CONFIG['default_f'], FACE_CONFIG['default_t'])
    end

    morphed_photo
  end

  # Shuffle photo object
  def get_shuffle_photo(number)
    get_shuffle(number: number).photo
  rescue
    nil
  end

  # Params { :x, :y, :w, :h }
  def crop(params)
    # 'user_photo' file path on filesystem
    image_path = self.user_photo.current_path

    # Call crop script, set 'image_path' to new file
    tool = FaceMorphing.new
    image_path = tool.cropped(image_path, params)
    if image_path
      self.cropped_user_photo = File.open(image_path)
      user_data['crop'] = [params[:x], params[:y], params[:w], params[:h]].join ','
    else
      self.remove_cropped_user_photo!
    end

    generate_detected_user_photo

    save!
  end

  def reset_crop
    self.remove_cropped_user_photo!
    generate_detected_user_photo

    save!
  end

  # Params { :overlay => 'black_female', :mask_file => PNG file }
  def testmask(params)
    # 'user_photo' file path on filesystem
    image_path = self.student_photo.current_path

    race, gender = $1, $2 if params[:overlay] =~ /^(.+)_([^_]+)$/
    unless race.present? && gender.present?
      raise "Bad overlay: #{params[:overlay]}"
    end

    mask_file = params[:mask_file].try :tempfile
    unless mask_file
      raise "Bad mask_file"
    end

    # Call morphing script, set 'image_path' to new file
    tool = FaceMorphing.new
    image_path = tool.morphed(image_path, gender, race, FACE_CONFIG['default_f'], FACE_CONFIG['default_t'], mask_file.path)
    unless image_path
      raise "!testmask"
    end

    image_path
  end

  # Stored crop params
  def crop_select
    if crop_params
      crop = crop_params.split(',').map{|n| n.to_f }
      crop[2] += crop[0]
      crop[3] += crop[1]

      crop
    else
      []
    end
  end

  MORPHING_FILES = %w(user_photo overlay_photo mask_photo).freeze
  MORPHING_PARAMS = %w(data_f data_t cmd_line).freeze
  MORPHING_RESULT = %w(detected_photo morphed_photo).freeze
  MORPHING_ALL = (MORPHING_FILES + MORPHING_PARAMS + MORPHING_RESULT).freeze

  # Copy uploaded photos and store their names in user_data
  def set_morphing_page_params(params)
    tool = FaceMorphing.new
    changed = false
    user_photo_changed = false

    if params[:commit] =~ /reset/i
      # Reset
      MORPHING_ALL.each do |opt|
        user_data.delete "morphing_#{opt}"
      end

      save!
    else
      MORPHING_FILES.each do |photo_id|
        photo_file = params[photo_id].try(:tempfile)
        if photo_file
          file_name = tool.save_morphing_photo(photo_file, photo_id)

          user_data["morphing_#{photo_id}"] = file_name # morphing_user_photo
          changed ||= true
          user_photo_changed ||= true if photo_id == 'user_photo'
        end
      end

      MORPHING_PARAMS.each do |opt|
        if user_data["morphing_#{opt}"] != params[opt]
          user_data["morphing_#{opt}"] = params[opt]
          changed ||= true
        end
      end
    end

    if user_photo_changed
      # Detected
      image_path = tool.get_morphing_photo(user_data['morphing_user_photo'])
      detected_photo = tool.detected(image_path)
      if detected_photo
        photo_file = File.open(detected_photo, 'rb')
        user_data['morphing_detected_photo'] = tool.save_morphing_photo(photo_file, 'detected_photo')
      else
        user_data.delete 'morphing_detected_photo'
      end

      save!
    end

    if changed
      # Morphed
      image_path = tool.get_morphing_photo(user_data['morphing_user_photo'])
      overlay_path = tool.get_morphing_photo(user_data['morphing_overlay_photo'])
      mask_path = tool.get_morphing_photo(user_data['morphing_mask_photo'])
      f = user_data['morphing_data_f']
      t = user_data['morphing_data_t']

      if image_path && overlay_path && f && t && (morphed_photo = tool.run_morphing(image_path, overlay_path, f, t, mask_path, user_data['morphing_cmd_line']))
        photo_file = File.open(morphed_photo, 'rb')
        user_data['morphing_morphed_photo'] = tool.save_morphing_photo(photo_file, 'morphed_photo')
      else
        user_data.delete 'morphing_morphed_photo'
      end

      save!
    end

    changed
  end

  # Get morphing page params
  def get_morphing_page_params(params)
    %w(data_f data_t cmd_line).each do |opt|
      params[opt] = user_data["morphing_#{opt}"]
    end
  end

  # Get morphing page photo
  def get_morphing_page_photo(params)
    photo_id = params[:type]
    unless %w(user_photo overlay_photo mask_photo detected_photo morphed_photo).include? photo_id
      raise "Unknown type #{photo_id}"
    end

    photo_id = "morphing_#{photo_id}"
    if user_data[photo_id].present?
      tool = FaceMorphing.new
      file_path = tool.get_morphing_photo(user_data[photo_id])

      file_path.exist? &&  file_path
    end
  end

  # Pledge of Inclusion status
  def pledge_of_inclusion_applied?
    user_data['pledge_of_inclusion_at'].present?
  end

  # Posted to facebook
  def pledge_of_inclusion_facebook?
    user_data['pledge_of_inclusion_fb_shared'].true?
  end

  # Update Pledge of Inclusion status
  # params: { :fb_shared => true }
  def update_pledge_of_inclusion(params)
    user_data['pledge_of_inclusion_fb_shared'] = (params[:fb_shared] == true || params[:fb_shared] == 'true')
    user_data['pledge_of_inclusion_at'] = Time.now

    save
  end
end
