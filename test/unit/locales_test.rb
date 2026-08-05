require File.expand_path('../test_helper', __dir__)

class LocalesTest < ActiveSupport::TestCase
  LOCALE_DIR = File.expand_path('../../config/locales', __dir__)

  # All leaf key paths of a locale file, e.g. "activerecord.attributes.
  # issue_datetime.start_time". The files nest, so comparing top-level keys
  # would miss a string missing deeper down.
  def leaf_keys(locale)
    tree = YAML.safe_load_file(File.join(LOCALE_DIR, "#{locale}.yml")).fetch(locale)
    collect_leaves(tree).sort
  end

  def collect_leaves(node, prefix = [])
    node.flat_map do |key, value|
      path = prefix + [key]
      value.is_a?(Hash) ? collect_leaves(value, path) : [path.join('.')]
    end
  end

  test 'en and ja define the same keys' do
    # Every string ships in both languages; a key added to one file only
    # fails here instead of falling back silently in production.
    assert_equal leaf_keys('en'), leaf_keys('ja')
  end
end
