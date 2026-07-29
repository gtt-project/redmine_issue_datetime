class IssueDatetime < ApplicationRecord
  belongs_to :issue

  validates :issue_id, uniqueness: true
  validate :validate_range

  def blank_times?
    starts_at.nil? && ends_at.nil?
  end

  private

  def validate_range
    if starts_at && ends_at && ends_at < starts_at
      errors.add(:ends_at, :invalid)
    end
  end
end
