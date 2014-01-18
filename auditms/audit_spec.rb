require 'spec_helper'

describe Audit do
  subject do
    audit_programs('Program 1').audits.create! :planned_audit_start_date => '02.08.2011', :planned_audit_end_date => '21.08.2011',
                                               :audit_name => 'name', :audit_type => audit_types('CMMI-DEV audit'),
                                               :service_line_id => org_units('AZZ DACH').org_unit_id, :service_area_id => org_units('AT Austria').org_unit_id,
                                               :site_name => 'Site', :country => countries('Finland'), :audit_status => :planned, :confidentiality => :internal
  end

  it "should create fixture" do
    audit = audits('Audit 2 PIL')
    audit.save!
  end

  context 'should validates' do
    it 'should should validate audit_type change' do
      expect {
        subject.audit_type = audit_types('PIL audit')
        subject.save!
      }.to raise_error /does not belong to Audit Program Type/
    end

    it 'should validate :audit_sub_type belongs to :audit_type' do
      audit = audits('Audit 1 ISO')
      audit.valid?.should == true

      expect {
        audit.audit_sub_type = audit_sub_types('SCAMPI A')
        audit.save!
      }.to raise_error /not belong to Audit Type/
    end

    it 'should validate CMMI Capability Level: belongs to AuditType' do
      audit = audits('Audit 1 ISO')
      audit.valid?.should == true

      expect {
        audit.audit_area_level_id = audit_levels('CL1').id
        audit.save!
      }.to raise_error /not belong to Audit Type/
    end

    it 'should validate planned dates' do
      audit = audits('Audit 1')

      expect {
        audit.planned_audit_start_date = Time.now
        audit.planned_audit_end_date  = Time.now - 1.day
        audit.save!
      }.to raise_error /has wrong start\/end dates/
    end

    it 'should validate actual dates' do
      audit = audits('Audit 1')

      expect {
        audit.actual_audit_start_date = Time.now
        audit.actual_audit_end_date  = Time.now - 1.day
        audit.save!
      }.to raise_error /has wrong start\/end dates/
    end
  end

  it 'should set approval dates' do
    subject.approved_by_unit_head_date?.should == false
    subject.approved_by_unit_head_date=(Time.now)
    subject.approved_by_unit_head_date?.should == true

    subject.approved_by_quality_head_date?.should == false
    subject.approved_by_quality_head_date=(Time.now)
    subject.approved_by_quality_head_date?.should == true
  end

  it 'should set date of approval' do
    audit = audits('Audit 1')
    audit.plan_approved?.should == false
    audit.result_approved?.should == false

    audit.lock_audit_plan(true)
    audit.approve_result(true)

    audit.save.should == true
  end

  it 'should freeze audit changes' do
    audit = audits('Audit 1')
    audit.plan_approved?.should == false
    audit.lock_audit_plan(true)
    audit.plan_approved?.should == true
    audit.save

    expect {
      audit.audit_name = audit.audit_name + ' change'
      audit.save!
    }.to raise_error /is frozen/

    audit.destroy
    audit.destroyed?.should == false
  end

  it 'should find lead auditor' do
    audit = audits('Audit 1')
    audit.lead_auditor.should == auditors(:lead_auditor1)
  end

  it 'should check user for team membership' do
    audit = audits('Audit 1')
    user = User.new :username => 'aaaa'
    audit.team_member?(user).should == false

    user = User.new :username => audit.auditors.first.employee_id # from team
    audit.team_member?(user).should == true
  end

  it 'should find all audits by program and type' do
    Audit.all_by_program_and_type(audit_programs('Program 1'), audit_types('CMMI-DEV audit')).should_not be_empty
  end

  it 'planned_audit_month' do
    ap subject
    subject.planned_audit_month?(2011, 7).should be_false
    subject.planned_audit_month?(2011, 8).should be_true
    subject.planned_audit_month?(2011, 9).should be_false
  end

  it 'planned_audit_quarter' do
    subject.planned_audit_quarter?(2011, 1).should be_false
    subject.planned_audit_quarter?(2011, 2).should be_false
    subject.planned_audit_quarter?(2011, 3).should be_true
    subject.planned_audit_quarter?(2011, 4).should be_false
  end

  it 'should list auditors in order' do
    audit = audits('Audit 1')
    audit.auditors_sorted_by_role.first.should == auditors(:lead_auditor1)
  end

  it 'should list available_item_categories goals' do
    Seed::CmmiAuditItems.run(Rails.root.join("db/seed", "CMMI model structure.xls"))
    audit = audits('CMMI-DEV audit')

    # Select all scope
    audit.audit_area_categories.each  do |area|
      unless area.generic?
        audit.audit_areas.create! :audit_area_category => area
      end
    end

    ap audit.available_item_categories.first
    audit.available_item_categories.should_not be_empty

    generic_practices_count = 0
    audit.available_item_categories.each do |area|
      area[:audit_item_categories].each do |item|
        if item[:audit_item_category_code].starts_with? 'GP'
          generic_practices_count += 1
        end
      end
    end
    generic_practices_count.should be > 100
  end

  it 'should list available_item_categories for PIL' do
    audit = audits('Audit 2 PIL')
    ap audit.audit_area_categories
    ap audit.audit_areas

    audit.audit_area_categories.should_not be_empty
    audit.audit_areas.should_not be_empty
    audit.audit_item_categories.should_not be_empty

    ap audit.available_item_categories
    audit.available_item_categories.should_not be_empty
  end

  #it 'should send_for_approval' do
  #  mock_current_user
  #  audit = audits('Audit 1')
  #  audit.send_for_approval(nil)
  #end

  it 'should filter by id' do
    Audit.filter(:audit_type_id => audit_types('CMMI-DEV audit')).count.should > 0
    Audit.filter(:audit_type_id => -1).count.should == 0
  end

  it 'should filter by string' do
    Audit.filter(:audit_name => "audit").count.should > 0
    Audit.filter(:audit_name => "auditauditauditaudit").count.should == 0
  end

  it 'should return default level for category' do
    audit = audits('CMMI-DEV audit')

    audit.audit_area_category_level(nil).should == audit.audit_area_level_id
  end

  it 'should not update audit_areas in frozen audit' do
    audit = audits('Audit 1')
    audit.plan_approved = true
    audit.save.should == true
    audit.select_audit_areas({}).should == false
  end

  it 'should update audit_areas' do
    audit = audits('Audit 1')
    audit.audit_areas.should be_empty

    #ap AuditAreaCategory.all
    selected_categories = {}
    area_category = AuditAreaCategory.find_by_audit_area_code 'REQM'
    area_category.should_not be_nil
    selected_categories[area_category.id.to_s] = { :selected => true }

    audit.select_audit_areas(:audit_area_categories => selected_categories).should == true
    audit.audit_areas.should_not be_empty

    # delete
    selected_categories = {}
    audit.select_audit_areas(:audit_area_categories => selected_categories).should == true
    audit.audit_areas.should be_empty
  end

  it 'should return planned audit start/end dates as period string' do
    audit = audits('Audit 1')
    audit.planned_audit_period.should == "2011-11-30 - 2011-12-30"
  end

  it 'should set planned audit start/end dates from period string' do
    audit = audits('Audit 1')
    audit.planned_audit_period = "2012-02-01 - 2012-02-15"
    audit.planned_audit_period.should == "2012-02-01 - 2012-02-15"
  end

  it 'should scope by audit_type_id' do
    pil = audit_types('PIL audit')
    #pp AuditType.all
    #pp Audit.where(:audit_type_id => pil).all
    #pp Audit.by_audit_type(pil)
    Audit.where(:audit_type_id => pil).all.should == Audit.by_audit_type(pil).all
  end

  it 'should return possible_previous_audits' do
    a = audits('Audit 1')
    a.possible_previous_audits.should_not be_empty

    a.possible_previous_audits.each do |prev|
      prev.should_not == a
      prev.audit_type.should == a.audit_type
    end
  end

  it 'should return audits with_non_conformances' do
    Audit.with_non_conformances.each do |audit|
      pp audit
      audit.findings.count.should be > 0
      audit.audit_program_type_name.should == "ISO"
    end
  end

  it 'should return audits with_overdue_activities' do
    finding_actions('Audit 2 PIL finding 1 action 1').action_due_date = Date.yesterday
    finding_actions('Audit 2 PIL finding 1 action 1').action_status = :ongoing
    finding_actions('Audit 2 PIL finding 1 action 1').save!

    a = audits('Audit 2 PIL')
    #pp a.finding_actions
    a.finding_actions.should include finding_actions('Audit 2 PIL finding 1 action 1')

    #pp Audit.with_overdue_activities
    Audit.with_overdue_activities.should include(a)

    Audit.with_overdue_activities.each do |audit|
      audit.finding_actions.count.should be > 0
    end
  end

  it 'should scope by date period' do
    #pp Audit.all
    Audit.in_period(nil, nil).should be_empty
    Audit.in_period('2011-01-01', Date.today).should_not be_empty
    Audit.in_period(100.years.ago, Date.today).should_not be_empty
    Audit.in_period(100.years.ago, 50.years.ago).should be_empty

    audit = audits('Audit 2 PIL')
    audit.planned_audit_start_date.should be < audit.planned_audit_end_date
    Audit.in_period(audit.planned_audit_start_date, audit.planned_audit_end_date).should include(audit)
    Audit.in_period(audit.planned_audit_start_date, audit.planned_audit_start_date).should include(audit)
    Audit.in_period(audit.planned_audit_end_date, audit.planned_audit_end_date).should include(audit)

    # inside
    Audit.in_period(audit.planned_audit_start_date + 1.day, audit.planned_audit_end_date - 1.day).should include(audit)
    # outside
    Audit.in_period(audit.planned_audit_start_date - 1.day, audit.planned_audit_end_date + 1.day).should include(audit)

    # cross
    Audit.in_period(audit.planned_audit_start_date + 1.day, audit.planned_audit_end_date + 1.day).should include(audit)
    Audit.in_period(audit.planned_audit_start_date - 1.day, audit.planned_audit_end_date - 1.day).should include(audit)

    # before
    Audit.in_period(audit.planned_audit_start_date - 10.day, audit.planned_audit_start_date - 1.day).should_not include(audit)
    # after
    Audit.in_period(audit.planned_audit_end_date + 1.day, audit.planned_audit_end_date + 10.day).should_not include(audit)

    # single start
    Audit.in_period(audit.planned_audit_start_date, nil).should include(audit)
    Audit.in_period(audit.planned_audit_start_date + 1.day, nil).should include(audit)
    Audit.in_period(audit.planned_audit_start_date - 1.day, nil).should_not include(audit)

    # single end
    Audit.in_period(audit.planned_audit_end_date, nil).should include(audit)
    Audit.in_period(audit.planned_audit_end_date - 1.day, nil).should include(audit)
    Audit.in_period(audit.planned_audit_end_date + 1.day, nil).should_not include(audit)
  end

  it 'should find audit_area by code' do
    audit = audits('Audit 2 PIL')
    audit.cache_audit_areas

    area = audit.audit_areas.first
    area_code = area.audit_area_code

    audit.audit_area(area_code).should == area
  end

  context "OrgUnit" do
    subject { audits('Audit 2 PIL') }

    it "should return Service line" do
      subject.service_line.should == org_units('AZZ DACH')
    end

    it "should set Service line by unit" do
      subject.service_line = org_units('EZZ Enterprise Solutions')
      subject.service_line.should == org_units('EZZ Enterprise Solutions')
    end

    it "should return Service area" do
      subject.service_area.should == org_units('AT Austria')
    end

    it "should set Service area by unit" do
      subject.service_area = org_units('AEZZ Enterprise Solutions')
      subject.service_area.should == org_units('AEZZ Enterprise Solutions')
    end

    it "should validate Service area unit" do
      subject.service_area = org_units('AZZ DACH')
      expect {
        subject.save!
      }.to raise_error /must be Service area/
    end

    it "should validate Service line unit" do
      subject.service_line = org_units('AT Austria')
      expect {
        subject.save!
      }.to raise_error /must be Service line/
    end

    it "should validate Service area belongs to Service line" do
      subject.service_line.should == org_units('AZZ DACH')

      subject.service_area = org_units('AT Austria')
      expect {
        subject.save!
      }.not_to raise_error

      subject.service_area = org_units('EAZ SAP')
      expect {
        subject.save!
      }.to raise_error /must belong to Service line/
    end

    it "should update_org_units" do
      params = { :service_line_name => org_units('AZZ DACH').org_unit_name,
                 :service_area_name => org_units('AT Austria').org_unit_name,
                 :service_practice_name => org_units('AEZZ Enterprise Solutions').org_unit_name }

      subject.update_org_units(params)
      subject.service_line.should == org_units('AZZ DACH')
      subject.service_area.should == org_units('AT Austria')
      subject.service_practice.should == org_units('AEZZ Enterprise Solutions')

      params.should be_empty
    end
  end

  context 'enums' do
    it "should set audit_status" do
      subject.audit_status = nil
      subject.audit_status_planned?.should == false
      subject.audit_status = :planned
      subject.audit_status_planned?.should == true
    end

    it "should set confidentiality" do
      subject.confidentiality = nil
      subject.confidentiality_internal?.should == false
      subject.confidentiality = :internal
      subject.confidentiality_internal?.should == true
    end

  end

  it "should return audit is_pil_nonconfidential" do
    audit = audits('Audit 2 PIL')
    audit.confidentiality = :confidential
    audit.is_pil_nonconfidential.should == false

    audit.confidentiality = :internal
    audit.is_pil_nonconfidential.should == true
  end

end
