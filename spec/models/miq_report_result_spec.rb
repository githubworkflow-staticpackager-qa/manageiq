RSpec.describe MiqReportResult do
  before do
    EvmSpecHelper.local_miq_server

    @user1 = FactoryBot.create(:user_with_group)
  end

  it "#_async_generate_result" do
    task = FactoryBot.create(:miq_task)
    EvmSpecHelper.local_miq_server
    report = MiqReport.create(
        :name          => "VMs based on Disk Type",
        :title         => "VMs using thin provisioned disks",
        :rpt_group     => "Custom",
        :rpt_type      => "Custom",
        :db            => "VmInfra",
        :cols          => ["name"],
        :col_order     => ["name"],
        :headers       => ["Name"],
        :order         => "Ascending",
        :template_type => "report"
    )
    report.generate_table(:userid => "admin")
    task.miq_report_result = report.build_create_results({:userid => "admin"}, task.id)
    task.miq_report_result._async_generate_result(task.id, :txt, :user => @user1)
    task.reload
    expect(task.state).to eq MiqTask::STATE_FINISHED
  end

  describe "#friendly_title" do
    let(:report_title) { "VMs using thin provisioned disks" }
    let(:report) { FactoryBot.create(:miq_report, :title => report_title) }
    let(:report_result_for_report) { FactoryBot.create(:miq_report_result, :miq_report_id => report.id, :report => report) }
    let(:widget_title) { "Widget: VMs using thin provisioned disks" }
    let(:widget) { FactoryBot.create(:miq_widget, :widget => widget_title) }
    let(:widget_content) { FactoryBot.create(:miq_widget_content, :miq_widget => widget) }
    let(:report_for_widget) { FactoryBot.create(:miq_report, :title => widget_title) }
    let(:report_result_for_widget) { FactoryBot.create(:miq_report_result, :miq_report => report_for_widget, :report => report_for_widget, :report_source => MiqWidget::WIDGET_REPORT_SOURCE) }

    it "display title for widget" do
      expect(report_result_for_report.friendly_title).to eq(report_title)
    end

    it "display title for widget" do
      expect(report_result_for_widget.friendly_title).to eq(widget_title)
    end
  end

  context "report result created by User 1 with current group 1" do
    before do
      @report_1 = FactoryBot.create(:miq_report)
      group_1 = FactoryBot.create(:miq_group)
      group_2 = FactoryBot.create(:miq_group)
      @user1.miq_groups << group_1
      @report_result1 = FactoryBot.create(:miq_report_result, :miq_report_id => @report_1.id, :miq_group => group_1)
      @report_result2 = FactoryBot.create(:miq_report_result, :miq_report_id => @report_1.id, :miq_group => group_1)
      @report_result_nil_report_id = FactoryBot.create(:miq_report_result)

      @report_2 = FactoryBot.create(:miq_report)
      @report_result3 = FactoryBot.create(:miq_report_result, :miq_report_id => @report_2.id, :miq_group => group_2)
      User.current_user = @user1
    end

    describe ".with_report" do
      it "returns report all results without nil report_id" do
        report_result = MiqReportResult.with_report
        expect(report_result).to match_array([@report_result1, @report_result2, @report_result3])
        expect(report_result).not_to include(@report_result_nil_report_id)
      end

      it "returns only requested report results" do
        report_result = MiqReportResult.with_report(@report_result1.miq_report_id)
        expect(report_result).to match_array([@report_result1, @report_result2])
        expect(report_result).not_to match_array([@report_result3, @report_result_nil_report_id])
      end
    end

    describe ".with_current_user_groups" do
      it "returns report results by generated by user 1, non-admin user logged" do
        report_result = MiqReportResult.with_current_user_groups
        expect(report_result).to match_array([@report_result1, @report_result2])
        expect(report_result).not_to match_array([@report_result3, @report_result_nil_report_id])
      end

      it "returns report all results with groups, admin user logged" do
        admin_role = FactoryBot.create(:miq_user_role, :features => MiqProductFeature::REPORT_ADMIN_FEATURE, :read_only => false)
        User.current_user.current_group.miq_user_role = admin_role
        report_result = MiqReportResult.with_current_user_groups
        expected_reports = [@report_result1, @report_result2, @report_result3]
        expect(report_result).to match_array(expected_reports)
      end
    end
  end

  context "persisting generated report results" do
    before do
      5.times do |i|
        vm = FactoryBot.build(:vm_vmware)
        vm.evm_owner_id = @user1.id               if i > 2
        vm.miq_group_id = @user1.current_group.id if vm.evm_owner_id || (i > 1)
        vm.save
      end

      @report_theme = 'miq'
      @show_title   = true
      @options = MiqReport.graph_options({:title => "CPU (Mhz)", :type => "Line", :columns => ["col"]})

      allow(ManageIQ::Reporting::Charting).to receive(:detect_available_plugin).and_return(ManageIQ::Reporting::C3Charting)
    end

    it "should save the original report metadata and the generated table as a binary blob" do
      MiqReport.seed_report(name = "Vendor and Guest OS")
      rpt = MiqReport.where(:name => name).last
      rpt.generate_table(:userid => "test")
      report_result = rpt.build_create_results(:userid => "test")

      report_result.reload

      expect(report_result).not_to be_nil
      expect(report_result.report.kind_of?(MiqReport)).to be_truthy
      expect(report_result.binary_blob).not_to be_nil
      expect(report_result.report_results.kind_of?(MiqReport)).to be_truthy
      expect(report_result.report_results.table).not_to be_nil
      expect(report_result.report_results.table.data).not_to be_nil
    end

    it "should not include `extras[:grouping]` in the report column" do
      MiqReport.seed_report(name = "Vendor and Guest OS")
      rpt = MiqReport.where(:name => name).last
      rpt.generate_table(:userid => "test")
      report_result = rpt.build_create_results(:userid => "test")

      report_result.report
      report_result.report.extras[:grouping] = {"extra data" => "not saved"}
      report_result.save

      result_reload = MiqReportResult.last

      expect(report_result.report.kind_of?(MiqReport)).to be_truthy
      expect(result_reload.report.extras[:grouping]).to be_nil
      expect(report_result.report.extras[:grouping]).to eq("extra data" => "not saved")
    end

    context "for miq_report_result is used different miq_group_id than user's current id" do
      before do
        MiqUserRole.seed
        role = MiqUserRole.find_by(:name => "EvmRole-operator")
        @miq_group = FactoryBot.create(:miq_group, :miq_user_role => role, :description => "Group1")
        MiqReport.seed_report(@name_of_report = "Vendor and Guest OS")
      end

      it "has passed miq_group_id and not user's miq_group_id(can be changed during scheduling and generating)" do
        rpt = MiqReport.where(:name => @name_of_report).last
        rpt.generate_table(:userid => "test")
        report_result = rpt.build_create_results(:userid => "test", :miq_group_id => @miq_group.id) # passed group.id
        report_result.reload

        expect(@user1.current_group_id).not_to eq(@miq_group.id)
        expect(report_result.miq_group_id).to eq(@miq_group.id)
      end
    end
  end

  describe "#status" do
    let(:report_name) { "Vendor and Guest OS" }
    let(:task) { FactoryBot.create(:miq_task) }
    let(:miq_report_result) do
      MiqReport.seed_report(report_name)
      report = MiqReport.where(:name => report_name).last
      report.generate_table(:userid => "test")
      task.miq_report_result = report.build_create_results({:userid => "test"}, task.id)
      MiqReportResult.find_by(:miq_task_id => task.id)
    end

    it "returns 'Running' if associated task exists and report not ready" do
      expect(miq_report_result.status).to eq "Running"
    end

    it "returns 'Complete' if report generated and associated task exists" do
      task.update_status("Finished", "Ok", "Generate Report result")
      expect(miq_report_result.status).to eq "Complete"
    end

    it "returns 'Complete' if task ssociated with report deleted" do
      expect(miq_report_result.status).to eq "Running"
      task.update_status("Finished", "Ok", "Generate Report result")
      task.destroy
      miq_report_result.reload
      expect(miq_report_result.status).to eq "Complete"
    end
  end

  describe '#report_results_blank?' do
    let(:report_result) { FactoryBot.create(:miq_report_result) }
    subject { report_result.report_results_blank? }

    context 'report has a binary blob' do
      let(:binary_blob) { FactoryBot.create(:binary_blob) }
      before { report_result.binary_blob = binary_blob }

      context 'binary blob is empty' do
        it { is_expected.to be_truthy }
      end

      context 'binary blob has parts' do
        before { binary_blob.binary = "foo" }
        it { is_expected.to be_falsey }
      end
    end
  end

  describe "serializing and deserializing report results" do
    it "can serialize and deserialize an MiqReport" do
      report = FactoryBot.build(:miq_report)
      report_result = described_class.new

      report_result.report_results = report

      expect(report_result.report_results.to_hash).to eq(report.to_hash)
    end

    it "can serialize and deserialize a CSV" do
      csv = CSV.generate { |c| c << %w[foo bar] << %w[baz qux] }
      report_result = described_class.new

      report_result.report_results = csv

      expect(report_result.report_results).to eq(csv)
    end

    it "can serialize and deserialize a plain text report" do
      txt = <<~EOF
        +--------------+
        |  Foo Report  |
        +--------------+
        | Foo  | Bar   |
        +--------------+
        | baz  | qux   |
        | quux | corge |
        +--------------+
      EOF
      report_result = described_class.new

      report_result.report_results = txt

      expect(report_result.report_results).to eq(txt)
    end
  end

  describe ".counts_by_userid" do
    it "fetches counts" do
      u1 = FactoryBot.create(:user)
      u2 = FactoryBot.create(:user)
      FactoryBot.create(:miq_report_result, :userid => u1.userid)
      FactoryBot.create(:miq_report_result, :userid => u1.userid)
      FactoryBot.create(:miq_report_result, :userid => u2.userid)

      expect(MiqReportResult.counts_by_userid).to match_array([
        {:userid => u1.userid, :count => 2},
        {:userid => u2.userid, :count => 1}
      ])
    end
  end

  describe "#to_pdf" do
    let(:user)   { FactoryBot.create(:user) }
    let(:report) { FactoryBot.create(:miq_report, :title => report_title) }
    let(:report_result) do
      FactoryBot.create(:miq_report_result, :name => report.title, :miq_report_id => report.id, :report => report, :userid => user.userid)
    end

    context "with a normal report" do
      let(:report_title) { "VMs using thin provisioned disks" }
      let(:pdf_title)    { report_title }

      it "renders the report" do
        expect(PdfGenerator).to receive(:pdf_from_string).with(<<~EOHTML.chomp, "pdf_report.css")
          <head><style>@page{size: a4 landscape}@page{margin: 40pt 30pt 40pt 30pt}@page{@top{content: '#{pdf_title}';color:blue}}@page{@bottom-center{font-size: 75%;content: 'Report date: '}}@page{@bottom-right{font-size: 75%;content: 'Page  ' counter(page) ' of  ' counter(pages)}}</style></head><table class="table table-striped table-bordered "><thead><tr><tbody></tbody></table>
        EOHTML

        report_result.to_pdf
      end
    end

    context "with a report with single quotes in the name" do
      let(:report_title) { "Fred's VMs using thin provisioned disks" }
      let(:pdf_title)    { "Fred\\'s VMs using thin provisioned disks" }

      it "renders the report" do
        expect(PdfGenerator).to receive(:pdf_from_string).with(<<~EOHTML.chomp, "pdf_report.css")
          <head><style>@page{size: a4 landscape}@page{margin: 40pt 30pt 40pt 30pt}@page{@top{content: '#{pdf_title}';color:blue}}@page{@bottom-center{font-size: 75%;content: 'Report date: '}}@page{@bottom-right{font-size: 75%;content: 'Page  ' counter(page) ' of  ' counter(pages)}}</style></head><table class="table table-striped table-bordered "><thead><tr><tbody></tbody></table>
        EOHTML

        report_result.to_pdf
      end
    end
  end
end
