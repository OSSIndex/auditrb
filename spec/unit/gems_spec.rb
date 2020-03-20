require 'chelsea/gems'

RSpec.describe Chelsea::Gems do
  it "executes `gems` command successfully" do
    output = StringIO.new
    file = "chelsea.gemspec"
    options = {}
    command = Chelsea::Gems.new(file, options)

    command.execute(output: output)

    expect(output.string).to eq("")
  end
end
