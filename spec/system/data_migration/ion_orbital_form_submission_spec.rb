# frozen_string_literal: true
require "rails_helper"

RSpec.describe "Form submission for ion orbital", type: :system, mock_ezid_api: true, js: true do
  let(:user) { FactoryBot.create(:pppl_moderator) }
  let(:title) { "Effects of collisional ion orbit loss on tokamak radial electric field and toroidal rotation in an L-mode plasma" }
  let(:description) do
    "Ion orbit loss has been used to model the formation of a strong negative radial electric field Er in the tokamak edge, as well as edge momentum transport and toroidal rotation. To quantitatively measure ion orbit loss, an orbit-flux formulation has been developed and numerically applied to the gyrokinetic particle-in-cell code XGC. We study collisional ion orbit loss in an axisymmetric DIII-D L-mode plasma using gyrokinetic ions and drift-kinetic electrons. Numerical simulations, where the plasma density and temperature profiles are maintained through neutral ionization and heating, show the formation of a quasisteady negative Er in the edge. We have measured a radially outgoing ion gyrocenter flux due to collisional scattering of ions into the loss orbits, which is balanced by the radially incoming ion gyrocenter flux from confined orbits on the collisional time scale. This suggests that collisional ion orbit loss can shift Er in the negative direction compared to that in plasmas without orbit loss. It is also found that collisional ion orbit loss can contribute to a radially outgoing (counter-current) toroidal-angular-momentum flux, which is not balanced by the toroidal-angular-momentum flux carried by ions on the confined orbits. Therefore, the edge toroidal rotation shifts in the co-current direction on the collisional time scale."
  end
  let(:ark) { "ark:/88435/dsp01r494vp42z" }
  let(:collection) { "Princeton Plasma Physics Laboratory" }
  let(:publisher) { "Princeton University" }
  let(:doi) { "10.1088/1741-4326/acc815" }
  let(:keywords) { "ion orbit loss, radial electric field, tokamak edge plasmas, gyrokinetic simulations" }

  before do
    stub_datacite(host: "api.datacite.org", body: datacite_register_body(prefix: "10.1088"))
    stub_request(:get, "https://handle.stage.datacite.org/10.1088/1741-4326/acc815")
      .to_return(status: 200, body: "", headers: {})
    stub_s3
  end
  context "migrate record from dataspace" do
    it "produces and saves a valid datacite record" do
      sign_in user
      visit "/works/new"
      fill_in "title_main", with: title
      fill_in "description", with: description
      select "Creative Commons Attribution 4.0 International", from: "rights_identifier"
      fill_in "orcid_1", with: "0000-0002-9844-6972"
      fill_in "given_name_1", with: "Hongxuan"
      fill_in "family_name_1", with: "Zhu"
      click_on "Add Another Creator"
      fill_in "given_name_2", with: "T"
      fill_in "family_name_2", with: "Stoltzfus-Dueck"
      click_on "Add Another Creator"
      fill_in "given_name_3", with: "R"
      fill_in "family_name_3", with: "Hager"
      click_on "Add Another Creator"
      fill_in "given_name_4", with: "S"
      fill_in "family_name_4", with: "Ku"
      click_on "Add Another Creator"
      fill_in "given_name_5", with: "C.S."
      fill_in "family_name_5", with: "Chang"

      click_on "Additional Metadata"
      fill_in "keywords", with: keywords

      ## Funder Information
      # https://ror.org/01bj3aw27 == ROR for United States Department of Energy
      page.find(:xpath, "//table[@id='funding']//tr[1]//input[@name='funders[][ror]']").set "https://ror.org/01bj3aw27"
      page.find(:xpath, "//table[@id='funding']//tr[1]//input[@name='funders[][award_number]']").set "DE-AC02-09CH11466"
      click_on "Add Another Funder"
      page.find(:xpath, "//table[@id='funding']//tr[2]//input[@name='funders[][ror]']").set "https://ror.org/01bj3aw27"
      page.find(:xpath, "//table[@id='funding']//tr[2]//input[@name='funders[][award_number]']").set "DE-AC02- 05CH11231"
      click_on "Add Another Funder"
      page.find(:xpath, "//table[@id='funding']//tr[3]//input[@name='funders[][ror]']").set "https://ror.org/01bj3aw27"
      page.find(:xpath, "//table[@id='funding']//tr[3]//input[@name='funders[][award_number]']").set "SciDAC-4"
      click_on "Add Another Funder"
      # https://ror.org/00hx57361 == ROR for Princeton University
      page.find(:xpath, "//table[@id='funding']//tr[4]//input[@name='funders[][ror]']").set "https://ror.org/00hx57361"
      page.find(:xpath, "//table[@id='funding']//tr[4]//input[@name='funders[][award_number]']").set "n/a"
      click_on "Curator Controlled"
      fill_in "publisher", with: publisher
      fill_in "publication_year", with: 2023
      select collection, from: "collection_id"
      fill_in "doi", with: doi
      fill_in "ark", with: ark
      click_on "Create"
      expect(page).to have_content "marked as Draft"
      expect(page).to have_content "Creative Commons Attribution 4.0 International"
      click_on "Complete"
      expect(page).to have_content "awaiting_approval"
      ion_orbital_work = Work.last
      expect(ion_orbital_work.title).to eq title
      expect(ion_orbital_work.ark).to eq ark

      # Ensure the datacite record produced validates against our local copy of the datacite schema.
      # This will allow us to evolve our local datacite standards and test our records against them.
      datacite = PDCSerialization::Datacite.new_from_work(ion_orbital_work)
      expect(datacite.valid?).to eq true
      expect(datacite.to_xml).to be_equivalent_to(File.read("spec/system/data_migration/ion_orbital.xml"))
      export_spec_data("ion_orbital.json", ion_orbital_work.to_json)
    end
  end
end