# frozen_string_literal: true
require "rails_helper"

RSpec.describe "Creating and updating works", type: :system do
  let(:user) { FactoryBot.create(:princeton_submitter) }

  before do
    stub_datacite(host: "api.datacite.org", body: datacite_register_body(prefix: "10.34770"))
    stub_s3
  end

  it "Defaults correct values for resource_type and resource_type_general", js: true do
    sign_in user
    visit user_path(user)
    click_on "Submit New"
    fill_in "title_main", with: "Supreme"
    fill_in "creators[][given_name]", with: "Sonia"
    fill_in "creators[][family_name]", with: "Sotomayor"
    click_on "Create New"
    work = Work.last
    expect(work.resource.resource_type).to eq "Dataset"
    expect(work.resource.resource_type_general).to eq "Dataset"
  end

  it "Prevents empty title", js: true do
    sign_in user
    visit user_path(user)
    click_on "Submit New"
    fill_in "title_main", with: ""
    click_on "Create New"
    expect(page).to have_content "Must provide a title"
  end

  # this test depends of the fake ORCID server defined in spec/support/orcid_specs.rb
  it "Fills in the creator based on an ORCID ID", js: true do
    sign_in user
    visit new_work_path(params: { wizard: true })
    click_on "Add Another Creator"
    find("tr:last-child input[name='creators[][orcid]']").set "0000-0000-1111-2222"
    expect(find("tr:last-child input[name='creators[][given_name]']").value).to eq "Sally"
    expect(find("tr:last-child input[name='creators[][family_name]']").value).to eq "Smith"
  end

  it "Renders ORCID links for creators", js: true do
    resource = FactoryBot.build(:resource, creators: [PDCMetadata::Creator.new_person("Harriet", "Tubman", "1234-5678-9012-3456")])
    work = FactoryBot.create(:draft_work, resource:)

    sign_in user
    visit work_path(work)
    expect(page.html.include?('<a href="https://orcid.org/1234-5678-9012-3456"')).to be true
  end

  it "Renders in wizard mode when requested", js: true do
    draft_work = FactoryBot.create(:draft_work)
    draft_work_submitter = draft_work.created_by_user

    sign_in draft_work_submitter
    visit edit_work_path(draft_work, wizard: true)
    expect(page.html.include?("By initiating this new submission, we have reserved a draft DOI for your use")).to be true
  end

  it "Handles Rights field", js: true do
    resource = FactoryBot.build(:resource, creators: [PDCMetadata::Creator.new_person("Harriet", "Tubman", "1234-5678-9012-3456")])
    work = FactoryBot.create(:draft_work, resource:)
    user = work.created_by_user
    sign_in user
    visit edit_work_path(work)
    select "GNU General Public License", from: "rights_identifiers"
    click_on "Save Work"
    expect(work.reload.resource.rights_many.first.identifier).to eq "GPLv3"
  end

  it "Renders ResourceType and GeneralType", js: true do
    resource = FactoryBot.build(:resource)
    work = FactoryBot.create(:draft_work, resource:)

    sign_in user
    visit work_path(work)

    def value_for(label)
      page.find(:xpath, "//dt[contains(text(), '#{label}')]/following-sibling::dd[1]").text
    end

    expect(value_for("Resource Type")).to eq "Dataset"
    expect(value_for("General Type")).to eq "Dataset"
  end

  it "Renders individual contributors", js: true do
    resource = FactoryBot.build(:resource)
    resource.individual_contributors = []
    resource.individual_contributors << PDCMetadata::Creator.new_individual_contributor("Robert", "Smith", "1234-1234-1234-1234", "ProjectLeader", 1)
    resource.individual_contributors << PDCMetadata::Creator.new_individual_contributor("Simon", "Gallup", nil, "Other", 2)
    work = FactoryBot.create(:draft_work, resource:)

    sign_in user
    visit work_path(work)
    expect(page.html.match?(/Smith, Robert\s+\(Project Leader\)/)).to be true
    expect(page.html.include?("Gallup, Simon")).to be true
  end

  it "Encodes creators names properly", js: true do
    # Use a lastname with an apostrophe
    resource = FactoryBot.build(:resource)
    resource.creators << PDCMetadata::Creator.new_person("Hugh", "O'Neill")
    work = FactoryBot.create(:draft_work, resource:)

    sign_in user
    visit work_path(work)
    expect(page.html.include?("O'Neill, Hugh")).to be true
  end

  it "Renders organizational contributors", js: true do
    resource = FactoryBot.build(:resource)
    resource.organizational_contributors = []
    resource.organizational_contributors << PDCMetadata::Creator.new_organizational_contributor("Fellowship of The Ring", "https://ror.org/012345678", "Other")
    work = FactoryBot.create(:draft_work, resource:)

    sign_in user
    visit work_path(work)
    expect(page.html.match?(/Fellowship of The Ring\s+\(Other\)/)).to be true
  end

  context "datacite record" do
    let(:work) { FactoryBot.create :draft_work }

    before do
      stub_s3
      sign_in user
    end

    it "Renders an xml serialization of the datacite" do
      visit datacite_work_path(work)
      doc = Nokogiri.XML(page.html)
      nodeset = doc.xpath("/xmlns:resource")
      expect(nodeset).to be_instance_of(Nokogiri::XML::NodeSet)
    end
  end

  context "invalid datacite record" do
    let(:work) { FactoryBot.create :draft_work }
    let(:invalid_xml) { file_fixture("datacite_basic.xml").read.gsub("<creator", "<invalid") }

    before do
      stub_s3
      stub_ark
      sign_in user
      allow_any_instance_of(PDCMetadata::Resource).to receive(:to_xml).and_return(invalid_xml)
    end

    it "Validates the record and prints any errors", js: true do
      visit datacite_validate_work_path(work)
      expect(page).to have_content "This element is not expected"
    end
  end

  context "when editing a work" do
    let(:draft_work) { FactoryBot.create(:draft_work) }
    let(:awaiting_approval_work) { FactoryBot.create(:awaiting_approval_work) }
    let(:user) { draft_work.created_by_user }

    it "uses the wizard if the work is in draft" do
      sign_in user
      visit work_path(draft_work)
      expect(page.html.include?("/works/#{draft_work.id}/edit?wizard=true")).to be true
    end

    context "work is awaiting approval" do
      let(:awaiting_approval_work) { FactoryBot.create(:awaiting_approval_work) }
      let(:user) { awaiting_approval_work.created_by_user }

      it "does not use the wizard if the work once the work is not in draft" do
        sign_in user
        visit work_path(awaiting_approval_work)
        expect(page.html.include?("/works/#{awaiting_approval_work.id}/edit")).to be true
      end
    end

    it "allows users to modify the order of the creators", js: true do
      stub_datacite_doi
      creator = draft_work.resource.creators.first
      sign_in user
      visit edit_work_path(draft_work)
      click_on "Add Another Creator"
      # Fill in the ROR first to make sure we click out of it, and give it time to populate
      find("tr:last-child input[name='creators[][ror]']").set "https://ror.org/021nxhr62"
      find("tr:last-child input[name='creators[][given_name]']").set "Sally"
      find("tr:last-child input[name='creators[][family_name]']").set "Smith"
      # https://ror.org/021nxhr62 == ROR for National Science Foundation
      expect(page).to have_field("creators[][affiliation]", with: "National Science Foundation")
      first_creator_text = "#{creator.given_name} #{creator.family_name}"
      second_creator_text = "Sally Smith  National Science Foundation https://ror.org/021nxhr62"

      creator_text = page.all("tr")[1..2].map { |each| each.all("input").map(&:value) }.flatten.join(" ").strip
      expect(creator_text).to eq("#{first_creator_text}    #{second_creator_text}")

      # drag the first creator to the second creator
      source = page.all(".bi-arrow-down-up")[0].native
      target = page.all(".bi-arrow-down-up")[1].native
      builder = page.driver.browser.action
      builder.drag_and_drop(source, target).perform
      creator_text_after = page.all("tr")[1..2].map { |each| each.all("input").map(&:value) }.flatten.join(" ").strip

      # This is really strange, but my local machine likes to drag from bottom to top and CircleCI likes to drag
      #  from top to bottom.  So I am adding in trying the other direction when the first direction fails.
      # This will make the test pass more consistantly for everyone (I hope)
      if creator_text_after != "#{second_creator_text} #{first_creator_text}"
        builder.drag_and_drop(target, source).perform
        creator_text_after = page.all("tr")[1..2].map { |each| each.all("input").map(&:value) }.flatten.join(" ").strip
      end
      expect(creator_text_after).to eq("#{second_creator_text} #{first_creator_text}")
      click_on "Save Work"
      draft_work.reload
      expect(draft_work.resource.creators.last.given_name).to eq(creator.given_name)
      expect(draft_work.resource.creators.last.family_name).to eq(creator.family_name)
      expect(draft_work.resource.creators.first.given_name).to eq("Sally")
      expect(draft_work.resource.creators.first.family_name).to eq("Smith")
      expect(draft_work.resource.creators.first.affiliation_ror).to eq("https://ror.org/021nxhr62")
      expect(draft_work.resource.creators.first.affiliation).to eq("National Science Foundation")
    end

    it "allows users to modify the order of the contributors", js: true do
      sign_in user
      visit edit_work_path(draft_work)
      click_on "Additional Metadata"
      expect(page).to have_content("Additional Individual Contributors")
      find("tr:last-child input[name='contributors[][given_name]']").set "Robert"
      find("tr:last-child input[name='contributors[][family_name]']").set "Smith"
      click_on "Add Another Individual Contributor"
      find("tr:last-child input[name='contributors[][given_name]']").set "Simon"
      find("tr:last-child input[name='contributors[][family_name]']").set "Gallup"
      contributor_text = page.find("#contributors-table").find_all("tr").map { |each| each.all("input").map(&:value) }.flatten.join(" ").strip
      expect(contributor_text).to eq("Robert Smith  Simon Gallup")

      # drag the first contributor to the second contributor
      # Rows in other tables also match this, so index may need to change.
      source = page.all("#contributors-table .bi-arrow-down-up")[0].native
      target = page.all("#contributors-table .bi-arrow-down-up")[1].native
      builder = page.driver.browser.action
      builder.drag_and_drop(source, target).perform
      contributor_text_after = page.find("#contributors-table").find_all("tr").map { |each| each.all("input").map(&:value) }.flatten.join(" ").strip
      # This is really strange, but my local machine likes to drag from bottom to top and CircleCI likes to drag
      #  from top to bottom.  So I am adding in trying the other direction when the first direction fails.
      # This will make the test pass more consistantly for everyone (I hope)
      if contributor_text_after != "Simon Gallup  Robert Smith"
        builder.drag_and_drop(target, source).perform
        contributor_text_after = page.find("#contributors-table").find_all("tr").map { |each| each.all("input").map(&:value) }.flatten.join(" ").strip
      end
      expect(contributor_text_after).to eq("Simon Gallup  Robert Smith")
      click_on "Save Work"
      draft_work.reload

      expect(draft_work.resource).not_to be nil
      expect(draft_work.resource.individual_contributors).not_to be_empty
      expect(draft_work.resource.individual_contributors.last.given_name).to eq("Robert")
      expect(draft_work.resource.individual_contributors.last.family_name).to eq("Smith")
    end
  end

  context "when editing an existing draft Work with uploaded files" do
    let(:work) { FactoryBot.create(:draft_work) }
    let(:user) { work.created_by_user }

    let(:s3_query_service_double) { instance_double(S3QueryService) }

    let(:file1) { FactoryBot.build :s3_file, filename: "#{work.doi}/#{work.id}/us_covid_2020.csv", work: }

    let(:file2) { FactoryBot.build :s3_file, filename: "#{work.doi}/#{work.id}/us_covid_2019.csv", work: }

    let(:s3_data) { [file1, file2] }

    let(:bucket_url) do
      "https://example-bucket.s3.amazonaws.com/"
    end
    let(:drag_javascript) do
      <<-EOF
      const dragSource = document.querySelector('.uploads-row:first-child');
      const dropTarget = document.querySelector('.uploads-row:last-child');

      window.dragMock.dragStart(dragSource).delay(100).dragOver(dropTarget).delay(100).drop(dropTarget);
      EOF
    end

    before do
      sign_in user
      stub_s3(data: s3_data)

      work.save
      work.reload
      visit edit_work_path(work)
    end

    it "shows the uploads before and after errors", js: true do
      expect(page).to have_content "us_covid_2019.csv"
      fill_in "title_main", with: ""
      click_on "Save Work"
      expect(page).to have_content "Must provide a title"
      expect(page).to have_content "us_covid_2019.csv"
    end

    it "shows the uploads before and after a valid metadata save", js: true do
      expect(page).to have_content "us_covid_2019.csv"
      fill_in "title_main", with: "updated title"
      click_on "Save Work"
      expect(page).to have_content "updated title"
      expect(page).to have_content "us_covid_2019.csv"
    end
  end
end
