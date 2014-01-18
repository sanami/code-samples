class Audit < ActiveRecord::Base
  include ActionView::Helpers::TextHelper

  # AuditProgram
  belongs_to :audit_program

  # AuditType
  belongs_to :audit_type
  belongs_to :audit_sub_type
  has_many :audit_levels, :through => :audit_type

  # Location
  belongs_to :market_unit
  belongs_to :country

  # ISO - Certificate
  belongs_to :certificate
  belongs_to :previous_audit, :class_name => 'Audit'

  # Tieto projects under audit
  has_many :audit_instances, :dependent => :destroy

  # CMMI - Process areas; PIL - W2E processes
  belongs_to :audit_area_category_version
  has_many :audit_area_categories, :through => :audit_area_category_version
  has_many :audit_areas, :dependent => :destroy # as instances of selected 'audit_area_categories'

  # CMMI - Generic/specific practices; PIL - W2E subprocesses
  has_many :audit_items, :dependent => :destroy
  has_many :audit_item_categories, :through => :audit_areas

  # Team members
  has_many :auditors, :dependent => :destroy

  # Finding
  has_many :findings, :dependent => :destroy
  has_many :finding_actions, :dependent => :destroy
  has_many :audit_files, :dependent => :destroy

  # Enumerated attributes
  enum_attr :audit_status, %w(planned performed closed delayed on_hold cancelled) do
    label :on_hold => 'On Hold'
  end
  def audit_status_human; enums(:audit_status).label(audit_status); end

  enum_attr :audit_on_track, %w(yes no)
  def audit_on_track_human; enums(:audit_on_track).label(audit_on_track); end

  enum_attr :confidentiality, %w(internal confidential)
  def confidentiality_human; enums(:confidentiality).label(confidentiality); end

  # Protected attributes
  attr_protected :audit_program_id # can't change
  attr_protected :plan_approved, :result_approved
  attr_protected :send_for_approval_date, :send_for_approval_tieto_id
  attr_protected :approved_by_quality_head_date, :approved_by_quality_head_id
  attr_protected :approved_by_unit_head_date, :approved_by_unit_head_id
  attr_protected :last_changed_date, :last_changed_tieto_id

  # Scopes
  scope :by_audit_type, lambda {|audit_type| where(:audit_type_id => audit_type) }

  # All 'audits' which have 'auditors' with this 'emp_id'
  scope :by_team_member_tieto_id, lambda {|emp_id| joins(:auditors).where('LOWER(auditors.employee_id) = ?', emp_id.downcase) }
  scope :by_action_responsible_tieto_id, lambda {|emp_id| joins(:finding_actions).where('LOWER(finding_actions.action_responsible_id) = ?', emp_id.downcase).uniq }
  scope :by_audit_owner_tieto_id, lambda {|emp_id| where('LOWER(audit_owner_id) = ?', emp_id.downcase) }
  scope :by_contact_person_tieto_id, lambda {|emp_id| where('LOWER(contact_person_id) = ?', emp_id.downcase) }
  scope :by_site_facilitator_tieto_id, lambda {|emp_id| where('LOWER(site_facilitator_id) = ?', emp_id.downcase) }
  scope :by_unit_head_tieto_id, lambda {|emp_id| where('LOWER(unit_head_id) = ?', emp_id.downcase) }
  scope :by_quality_head_tieto_id, lambda {|emp_id| where('LOWER(quality_head_id) = ?', emp_id.downcase) }
  scope :ongoing_audits, where('? BETWEEN planned_audit_start_date AND planned_audit_end_date', Date.today)
  scope :next_audits, where('planned_audit_start_date BETWEEN ? AND ?', Date.tomorrow, 3.months.from_now)
  scope :upcoming_audits, where('planned_audit_start_date BETWEEN ? AND ?', Date.tomorrow, 31.days.from_now)
  scope :in_period, lambda { |from, to|
    if from.present? && to.present?
      if from.to_date > to.to_date
        from, to = to, from
      end
      where('(planned_audit_start_date <= ?) AND (? <= planned_audit_end_date)', to, from)
    else
      where('(? BETWEEN planned_audit_start_date AND planned_audit_end_date)', from || to)
    end
  }

  scope :iso_audits, lambda { where(:audit_type_id => AuditProgramType.find_by_audit_program_type(:iso).audit_types) }
  scope :not_iso_audits, lambda { where('audit_type_id NOT IN (?)', AuditProgramType.find_by_audit_program_type(:iso).audit_types) }

  # ISO audits with findings
  scope :with_non_conformances, lambda {
    iso_audits.joins(:findings).group('findings.audit_id').having('COUNT(findings.id) > 0')
  }

  scope :with_overdue_activities, lambda {
    joins(:finding_actions).where("action_status != ? AND action_due_date < ?", :closed, Date.today)
  }

  scope :with_missed_deadline, lambda {
    iso_audits.joins(:findings).where("iso_status != ? AND iso_closure_date < ?", :closed, Date.today)
  }

  # Waiting approval by Quality/Unit head
  scope :requiring_approval_by_quality_head, where('(send_for_approval_date IS NOT NULL) AND (approved_by_quality_head_date IS NULL)')
  scope :requiring_approval_by_unit_head, where('(approved_by_quality_head_date IS NOT NULL) AND (approved_by_unit_head_date IS NULL)')
  scope :approvable_as_quality_or_unit_head, lambda { |emp_id|
    where('((send_for_approval_date IS NOT NULL) AND (approved_by_quality_head_date IS NULL) AND
            (LOWER(quality_head_id) = ?) ) OR
           ((approved_by_quality_head_date IS NOT NULL) AND (approved_by_unit_head_date IS NULL) AND
            (LOWER(unit_head_id) = ?) )',
          emp_id.downcase, emp_id.downcase)
  }
  scope :approved_by_quality_or_unit_head, where('(approved_by_quality_head_date IS NOT NULL) OR (approved_by_unit_head_date IS NOT NULL)')

  # Delegations
  delegate :audit_program_name, :to => :audit_program, :prefix => false, :allow_nil => false
  delegate :audit_program_type, :to => :audit_program, :prefix => false, :allow_nil => false
  delegate :audit_program_type_name, :to => :audit_program, :prefix => false, :allow_nil => false
  delegate :org_unit_version, :to => :audit_program, :prefix => false, :allow_nil => false
  delegate :is_cmmi, :is_iso, :is_pil, :to => :audit_program, :prefix => false, :allow_nil => false
  delegate :audit_types, :to => :audit_program, :prefix => false, :allow_nil => false
  delegate :audit_type_name, :to => :audit_type, :prefix => false, :allow_nil => true
  delegate :audit_sub_type_name, :to => :audit_sub_type, :prefix => false, :allow_nil => true
  delegate :certificate_number, :to => :certificate, :prefix => false, :allow_nil => true
  delegate :country_code, :to => :country, :prefix => false, :allow_nil => true
  delegate :country_name, :to => :country, :prefix => false, :allow_nil => true
  delegate :market_unit_name, :to => :market_unit, :prefix => false, :allow_nil => true
  delegate :audit_name_with_program, :to => :previous_audit, :prefix => true, :allow_nil => true
  delegate :audit_area_category_version_name, :to => :audit_area_category_version, :prefix => false, :allow_nil => true

  # Validations
  auto_strip_attributes :audit_name, :site_name, :audit_comments, :other_criteria
  validates_presence_of :audit_name, :audit_type_id, :audit_program_id
  #TODO validates_presence_of :country_name, :site_name, :unless => lambda { |a| a.is_pil } # skip for PIL
  validates_associated :country, :audit_type, :audit_sub_type, :audit_program, :certificate
  #NOTE validates_associated :previous_audit # disabled for audits referencing each other
  validates_presence_of :planned_audit_start_date, :planned_audit_end_date # Dates
  validates_presence_of :planned_audit_period, :if => Proc.new { false }  # Used in form builder
  validates_presence_of :audit_status, :confidentiality, :if => lambda { |a| a.is_pil }

  # CMMI Capability Level
  validates_numericality_of :audit_area_level_id, :allow_nil => true, :only_integer => true

  # Tieto ID's own validator
  validates :quality_head_id, :employee_id => true
  validates :unit_head_id, :employee_id => true
  validates :audit_owner_id, :employee_id => true
  validates :contact_person_id, :employee_id => true
  validates :send_for_approval_tieto_id, :employee_id => true
  validates :approved_by_quality_head_id, :employee_id => true
  validates :approved_by_unit_head_id, :employee_id => true
  validates :last_changed_tieto_id, :employee_id => true
  validates :site_facilitator_id, :employee_id => true
  include EmployeeData
  employee_data :quality_head_id, :as => :quality_head
  employee_data :unit_head_id, :as => :unit_head
  employee_data :audit_owner_id, :as => :audit_owner
  employee_data :contact_person_id, :as => :contact_person
  employee_data :send_for_approval_tieto_id, :as => :send_for_approval_employee
  employee_data :approved_by_quality_head_id, :as => :approved_by_quality_head
  employee_data :approved_by_unit_head_id, :as => :approved_by_unit_head
  employee_data :last_changed_tieto_id, :as => :last_changed_employee
  employee_data :site_facilitator_id, :as => :site_facilitator

  validate do
    #if self.audit_type_id_changed?
    #  unless self.audit_areas.empty?
    #    errors[:audit_type_id] << "can't change when Audit Scope is defined"
    #  end
    #end

    if audit_program && audit_type && !audit_program.audit_types.exists?(audit_type_id)
      errors[:audit_type_id] << 'does not belong to Audit Program Type'
    end

    # :audit_sub_type belongs to :audit_type
    if audit_sub_type && audit_type && !audit_type.audit_sub_types.exists?(audit_sub_type_id)
      errors[:audit_sub_type_id] << 'does not belong to Audit Type'
    end

    # CMMI Capability Level: belongs to AuditType
    if self.audit_area_level_id && !self.audit_levels.exists?(self.audit_area_level_id)
      errors[:audit_area_level_id] << 'does not belong to Audit Type'
    end

    #TODO OrgUnit belongs to Certificate
    #if org_unit
    #  if certificate && !certificate.org_unit_in_scope?(self.org_unit)
    #    errors[:org_unit_name] << 'must be in Certificate scope'
    #    errors[:certificate_id] << 'must contains the OrgUnit'
    #  end
    #end

    # Service line
    if service_line_id? and !service_line.service_line?
      errors[:service_line_name] << "#{service_line_id} must be Service line unit"
    end

    # Service area
    if service_area_id? and !service_area.service_area?
      errors[:service_area_name] << "#{service_area_id} must be Service area unit"
    end

    # Service practice
    if service_practice_id? and !service_practice.service_practice?
      errors[:service_practice_name] << "#{service_practice_id} must be Service practice unit"
    end

    # Service area belongs to Service line
    if service_area_id? && service_area.service_line != service_line
      errors[:service_area_name] << "#{service_area_id} must belong to Service line #{service_line_id}"
    end

    # Service practice belongs to Service area
    if service_practice_id? && service_practice.service_area != service_area
      errors[:service_practice_name] << "#{service_practice_id} must belong to Service area #{service_area_id}"
    end

    # Wrong dates
    if !(planned_audit_start_date && planned_audit_end_date) || (planned_audit_start_date > planned_audit_end_date)
      errors[:planned_audit_period] << "has wrong start/end dates"
    end

    if actual_audit_start_date && actual_audit_end_date && (actual_audit_start_date > actual_audit_end_date)
      errors[:actual_audit_period] << "has wrong start/end dates"
    end

    # PIL audit
    if is_pil
      if audit_status_performed? || audit_status_closed?
        unless actual_audit_start_date? && actual_audit_end_date?
          errors[:actual_audit_period] << "is mandatory when Audit status is changed to 'Performed' or 'Closed'"
        end

        unless people_covered
          errors[:people_covered] << "is mandatory when Audit status is changed to 'Performed' or 'Closed'"
        end
      end
    end
  end

  before_save do
    # Last changed on
    unless changed_attributes.empty?
      self.last_changed_tieto_id = session[:user_employee_id] rescue nil #NOTE not accessible from tests
      self.last_changed_date = Time.now
    end
  end

  after_save do
    # Audit type CAN be changed and the scope will be lost after change
    if audit_type_id_changed?
      self.audit_areas.destroy_all # All audit_areas, audit_items, findings, actions
    end
  end

  # Freeze audit functionality
  validate do
    if audit_plan_frozen? && self.changed?
      #pp changed_attributes
      unless changed_attributes.size == 1 && changed_attributes.has_key?('result_approved') # can approve
        AuditPlanApprovedCallback.add_error_message(self)
      end
    end
  end
  before_destroy do
    if audit_plan_frozen? or audit_result_approved?
      AuditPlanApprovedCallback.add_error_message(self)
      return false #return false, to not destroy the element, otherwise, it will delete.
    end
  end

  # Sum of est_effort_non_billable/est_effort_billable
  def est_effort_total
    (est_effort_non_billable || 0) + (est_effort_billable || 0)
  end

  def audit_level_name
    if self.audit_area_level_id
      self.audit_levels.find_by_id(self.audit_area_level_id).try(:audit_level_name)
    end
  end

  # Country code with site name: "FI-Kilo"
  def country_site_name
    [country_code, site_name].join('-')
  end

  # Auditor with lead role
  def lead_auditor
    self.auditors.all.detect {|auditor| auditor.is_lead_auditor? }
  end

  # Service line
  def service_line
    org_unit_version.by_org_unit_id(self.service_line_id)
  end

  # Set by unit
  def service_line=(org_unit)
    self.service_line_id = org_unit.org_unit_id
  end

  # Service line name
  def service_line_name
    service_line.try(:org_unit_name)
  end

  # Service area
  def service_area
    org_unit_version.by_org_unit_id(self.service_area_id)
  end

  # Set by unit
  def service_area=(org_unit)
    self.service_area_id = org_unit.org_unit_id
  end

  # Service area name
  def service_area_name
    service_area.try(:org_unit_name)
  end

  # Service practice
  def service_practice
    org_unit_version.by_org_unit_id(self.service_practice_id)
  end

  # Set by unit
  def service_practice=(org_unit)
    self.service_practice_id = org_unit.org_unit_id
  end

  # Service practice name
  def service_practice_name
    service_practice.try(:org_unit_name)
  end

  # Update Service line/area/practice by names
  def update_org_units(params)
    # Units
    service_line = org_unit_version.service_lines.by_org_unit_name(params[:service_line_name]).first
    self.service_line_id = service_line.try(:org_unit_id)

    if service_line
      service_area = service_line.children.by_org_unit_name(params[:service_area_name]).first
      self.service_area_id = service_area.try(:org_unit_id)

      if service_area
        service_practice = service_area.children.by_org_unit_name(params[:service_practice_name]).first
        self.service_practice_id = service_practice.try(:org_unit_id)
      end
    end

    # Remove keys from params
    params.delete :service_line_name
    params.delete :service_area_name
    params.delete :service_practice_name
  end

  # Set Certificate by certificate_number
  def certificate_number=(num)
    self.certificate = Certificate.where(:certificate_number => num).first
  end

  # Set Country by country_name
  def country_name=(name)
    self.country = Country.where(:country_name => name).first
  end

  #TODO
  def previous_audit_audit_name_with_program=(name)
  end

  # Audit already was sent for approval
  def sent_for_approval?
    self.send_for_approval_date?
  end

  # If quality head is defined, audit plan can be sent for approval
  def sendable_for_approval?
    !sent_for_approval? && self.quality_head_correct?
  end

  # Audit already approved
  def approved_by_quality_head?
    self.approved_by_quality_head_date?
  end
  def approvable_by_quality_head?
    sent_for_approval? && !approved_by_quality_head?
  end

  # Audit already approved
  def approved_by_unit_head?
    self.approved_by_unit_head_date?
  end
  def approvable_by_unit_head?
    approved_by_quality_head? && !approved_by_unit_head?
  end

  # Is team member of audit
  def team_member?(user)
    self.auditors.find_each do |auditor|
      return true if user.is?(auditor.employee_id)
    end

    false
  end

  # Approved and saved earlier
  def audit_plan_frozen?
    plan_approved? and !plan_approved_changed?
  end

  # Approved and saved earlier
  def audit_result_approved?
    result_approved? and !result_approved_changed?
  end

  def self.all_by_program_and_type(audit_program, audit_type)
    find_all_by_audit_program_id_and_audit_type_id(audit_program, audit_type)
  end

  # Audit planned in this month
  def planned_audit_month? year, month
    t = Date.new year, month
    # Check start date only
    planned_audit_start_date.beginning_of_month <= t && t <= planned_audit_start_date.end_of_month
  end

  # Audit planned in this quarter
  def planned_audit_quarter? year, quarter
    t = Date.new year, (quarter*3-1)
    # Check start date only
    planned_audit_start_date.beginning_of_quarter <= t && t <= planned_audit_start_date.end_of_quarter
  end

  # Has audit area of this category
  def has_audit_area_category?(area_category)
    audit_areas.exists?(:audit_area_category_id => area_category)
  end

  # Default or selected level for category
  def audit_area_category_level(area_category)
    audit_area = self.audit_areas.where(:audit_area_category_id => area_category).first
    if audit_area
      audit_area.audit_area_level_id
    else
      self.audit_area_level_id # default
    end
  end

  # Update audit_areas based on params
  def select_audit_areas(params)
    # Freeze audit functionality
    if audit_plan_frozen?
      AuditPlanApprovedCallback.add_error_message(self) # 'Audit data is frozen'
      return false
    end

    # Other Audit criteria and reference models
    update_attributes! :other_criteria => params[:other_criteria]

    selected_categories = params[:audit_area_categories]

    # Freeze also defined in AuditArea validate
    if selected_categories
      selected_categories.each do |category_id, cat_params|
        #pp category_id, params
        area_category = AuditAreaCategory.find(category_id)

        audit_area = self.audit_areas.find_by_audit_area_category_id(area_category)

        if cat_params[:selected]
          # Create
          unless audit_area
            audit_area = self.audit_areas.create!(:audit_area_category => area_category)
          end

          audit_area.audit_area_level_id = cat_params[:level]
          audit_area.save!

        elsif audit_area
          # Remove
          self.audit_areas.delete audit_area
        end
      end
    else
      # Empty, delete all areas
      selected_categories = {}
    end

    # Clean "audit_areas" from categories not set in "selected_categories"
    self.audit_areas.find_each do |audit_area|
      unless selected_categories.has_key?(audit_area.audit_area_category_id.to_s) or selected_categories.has_key?(audit_area.audit_area_category_id)
        self.audit_areas.delete audit_area # do work with .all. collection
      end
    end

    true
  end

  # Sorted by auditor role, lead goes first
  def auditors_sorted_by_role
    self.auditors.by_auditor_role
  end

  # Audit areas => audit item categories, depends on audit type
  def available_item_categories
    all = []

    if is_cmmi
      generic_audit_area_category = audit_area_category_version.generic_audit_area_category

      audit_areas.each do |area|
        dat = {}
        dat[:id] = area.id
        dat[:audit_area_name] = area.audit_area_name
        dat[:audit_item_categories] = []

        # Specific
        area.audit_item_categories.only_practices.sorted_by_code.each do |cat|
          dat[:audit_item_categories] << {:id => cat.id, :full_name => cat.full_name, :audit_item_category_code => cat.audit_item_category_code, :audit_item_category_name => cat.audit_item_category_name}
        end

        # Generic
        generic_audit_area_category.audit_item_categories.only_practices.sorted_by_code.each do |cat|
          dat[:audit_item_categories] << {:id => cat.id, :full_name => cat.full_name, :audit_item_category_code => cat.audit_item_category_code, :audit_item_category_name => cat.audit_item_category_name}
        end

        all << dat
      end
    elsif is_pil
      # PIL
      all = audit_areas.as_json(:methods => :audit_area_name,
                                :include => {
                                :audit_item_categories => {:methods => :full_name} })
    end

    all
  end

  # Return audit item with selected 'audit_area_id'/'audit_item_category_id'
  def create_audit_item(audit_area_id, audit_item_category_id)
    unless audit_area_id.blank? || audit_item_category_id.blank?
      # Create audit item if not exist
      audit_item = self.audit_items.find_or_create_by_audit_area_id_and_audit_item_category_id(audit_area_id, audit_item_category_id)
      audit_item.save!
      audit_item
    else
      # Not selected
      #TODO delete empty audit items
      nil
    end
  end

  # Build audit finding based on params
  def finding_build(params)
    #ap params
    import_type = params[:_import_type]

    audit_item = create_audit_item(params['audit_area_id'], params['audit_item_category_id'])
    params['audit_item_id'] = audit_item ? audit_item.id : nil

    params.delete 'audit_item_category_id'
    params.delete 'audit_area_id'
    params.delete :_import_type

    if audit_item && (finding = audit_item.findings.first)
      # Action on existing finding
      case import_type
        when :leave_old
          return finding
        when :replace
          finding.update_attributes! params
          return finding
        else
          #TODO multiple findings in audit_item
      end
    end

    self.findings.build(params)
  end

  # Update audit finding attributes
  def finding_update(finding, params)
    if params['audit_area_id'].blank? && params['audit_item_category_id'].present?
      finding.errors.add :audit_area_id, 'can not be nil'
      return false
    end
    if params['audit_item_category_id'].blank? && params['audit_area_id'].present?
      finding.errors.add :audit_item_category_id, 'can not be nil'
      return false
    end

    audit_item = create_audit_item(params['audit_area_id'], params['audit_item_category_id'])
    params['audit_item_id'] = audit_item ? audit_item.id : nil

    params.delete 'audit_item_category_id'
    params.delete 'audit_area_id'

    params.delete 'pil_weight'
    params.delete 'pil_pil'
    params.delete 'pil_satisfaction'

    finding.update_attributes(params)
  end

  # Import audit findings
  def findings_import(params, current_user)
    file = params[:import_file].tempfile
    transaction do
      #findings.clear
      if is_cmmi
        Import::CmmiFindings.run(self, file.path)
      elsif is_iso
        Import::IsoFindings.run(self, file.path)
      elsif is_pil
        Import::PilFindings.run(self, file.path, params[:import_type].to_sym)
      else
        raise "Findings import for #{audit_program_type_name} not supported"
      end

      # Upload file
      create_audit_file(params[:import_file], params[:import_file].original_filename, current_user)
    end
  end

  # Upload audit file
  def create_audit_file(file, file_name, current_user = nil)
    audit_files.create! :audit_file => file, :audit_file_name => file_name, :audit_file_date => Time.now, :audit_file_uploader_id => current_user.try(:username)
  end

  # Export audit findings
  def findings_export
    if is_iso
      result = Export::IsoFindings.run(self)
      name = "DNV report.xls"
      [name, result]
    else
      raise "Findings export for #{audit_program_type_name} not supported"
    end
  end

  # Approve/lock/freeze audit plan
  def lock_audit_plan(lock)
    update_attribute :plan_approved, lock # update_column can't handle lock as String
  end

  # Approve audit results
  def approve_result(approve)
    update_attribute :result_approved, approve
  end

  # Sent for approval
  def send_for_approval(current_user)
    # Set date of send for approval
    update_column :send_for_approval_date, Time.now
    update_column :send_for_approval_tieto_id, current_user.username

    # Send mail
    if self.quality_head
      mail = UserMailer.approve_as_quality_head(self)
      mail.deliver
    end
  end

  # Approval
  def approve_as_quality_head(current_user)
    # Set date of approval
    update_column :approved_by_quality_head_date, Time.now
    update_column :approved_by_quality_head_id, current_user.username

    # Send mail
    if self.unit_head
      mail = UserMailer.approve_as_unit_head(self)
      mail.deliver
    end
  end

  # Approval
  def approve_as_unit_head(current_user)
    # Set date of approval
    update_column :approved_by_unit_head_date, Time.now
    update_column :approved_by_unit_head_id, current_user.username
  end

  # Apply search filters
  def self.filter(params)
    all = self

    # Search string
    [:audit_name].each do |field|
      if params[field].present?
        all = all.where("LOWER(#{field}) LIKE ?", "%#{params[field].downcase}%")
      end
    end

    #if params[:audit_name_with_program].present?
    #  all = all.joins(:audit_program).joins(:audit_program_type).where("LOWER(audit_name+' - '+audit_programs.year) LIKE ?", "%#{params[:audit_name_with_program].downcase}%")
    #end

    # Search by Id
    [:audit_type_id, :audit_program_id, :country_id, :market_unit_id, :service_line_id, :service_area_id].each do |field|
      if params[field].present?
        all = all.where(field => params[field])
      end
    end

    # Limit by Certificate
    if params[:certificate_number].present?
      all = all.joins(:certificate).where("certificates.certificate_number" => params[:certificate_number])
    end

    all
  end

  # Autocomplete for 'previous_audit'
  def previous_audit_autocomplete(params)
    all = Audit.filter :audit_name => params[:term], :audit_type_id => params[:audit_type_id], :certificate_number => params[:certificate_number]
    all = all.where('audits.id != ?', self.id)

    all = all.limit(100)

    all.map! {|obj| { :label => obj.audit_name_with_program, :value => obj.id } }

    [{:label => 'No audit', :value => nil}] + all
  end


  # Planned audit start - end dates as string
  def planned_audit_period
    [planned_audit_start_date, planned_audit_end_date].compact.join ' - '
  end

  # Set planned audit start/end dates from string
  def planned_audit_period=(str)
    dates = str.split ' - '
    self.planned_audit_start_date = dates[0]
    self.planned_audit_end_date = dates[1]
  end

  # Actual audit start - end dates as string
  def actual_audit_period
    [actual_audit_start_date, actual_audit_end_date].compact.join ' - '
  end

  # Set actual audit start/end dates from string
  def actual_audit_period=(str)
    dates = str.split ' - '
    self.actual_audit_start_date = dates[0]
    self.actual_audit_end_date = dates[1]
  end

  # Next audit start - end dates as string
  def next_audit_period
    [next_audit_start_date, next_audit_end_date].compact.join ' - '
  end

  # Set next audit start/end dates from string
  def next_audit_period=(str)
    dates = str.split ' - '
    self.next_audit_start_date = dates[0]
    self.next_audit_end_date = dates[1]
  end

  # Audit of same type, except self
  #TODO limit by certificate
  def possible_previous_audits
    if self.certificate
      Audit.by_audit_type(self.audit_type).where('id != ? AND certificate_id = ?', self.id, self.certificate)
    else
      Audit.by_audit_type(self.audit_type).where('id != ?', self.id)
    end
  end

  def audit_name_with_program
    "#{audit_name} - #{audit_program_name}"
  end

  # For fast access by process code
  def cache_audit_areas
    @cached_audit_areas = {}
    audit_areas.each do |area|
      @cached_audit_areas[area.audit_area_code] = area
    end
  end

  # Audit are by code
  #NOTE Call 'cache_audit_areas'
  def audit_area(audit_area_code)
    #@cached_audit_areas ||= {}
    #@cached_audit_areas[audit_area_code] ||= audit_areas.by_audit_area_code(audit_area_code).first
    @cached_audit_areas[audit_area_code]
  end

  # Update 'audit_areas'
  def calculate_improvement_proposals
    audit_areas.each do |area|
      area.update_improvement_proposal_count
    end
  end

  # PIL audit not classified as "Confidential"
  def is_pil_nonconfidential
    is_pil && !confidentiality_confidential?
  end

  # Delete PIL findings
  def delete_audit_areas(audit_area_ids)
    self.audit_areas.find(audit_area_ids).each do |audit_area|
      audit_area.audit_items.destroy_all
    end

    true
  end

end
# == Schema Information
#
# Table name: audits
#
#  id                             :integer(4)      not null, primary key
#  audit_program_id               :integer(4)
#  certificate_id                 :integer(4)
#  audit_name                     :string(255)
#  audit_type_id                  :integer(4)
#  audit_sub_type_id              :integer(4)
#  audit_status                   :string(255)
#  audit_area_level_id            :integer(4)
#  audit_comments                 :text
#  people_covered                 :integer(4)
#  audit_on_track                 :string(255)
#  confidentiality                :string(255)
#  other_criteria                 :text
#  service_line_id                :integer(4)
#  service_area_id                :integer(4)
#  service_practice_id            :integer(4)
#  market_unit_id                 :integer(4)
#  country_id                     :integer(4)
#  site_name                      :string(255)
#  sei_db_link                    :string(1000)
#  teamer_link                    :string(1000)
#  planned_audit_start_date       :date
#  planned_audit_end_date         :date
#  actual_audit_start_date        :date
#  actual_audit_end_date          :date
#  next_audit_start_date          :date
#  next_audit_end_date            :date
#  audit_owner_id                 :string(8)
#  contact_person_id              :string(8)
#  quality_head_id                :string(8)
#  unit_head_id                   :string(8)
#  site_facilitator_id            :string(8)
#  est_effort_non_billable        :integer(4)
#  est_effort_billable            :integer(4)
#  send_for_approval_date         :datetime
#  send_for_approval_tieto_id     :string(8)
#  approved_by_quality_head_date  :datetime
#  approved_by_quality_head_id    :string(8)
#  approved_by_unit_head_date     :datetime
#  approved_by_unit_head_id       :string(8)
#  last_changed_date              :datetime
#  last_changed_tieto_id          :string(8)
#  plan_approved                  :boolean(1)
#  result_approved                :boolean(1)
#  audit_area_category_version_id :integer(4)
#  previous_audit_id              :integer(4)
#  created_at                     :datetime        not null
#  updated_at                     :datetime        not null
#

