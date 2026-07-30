namespace :redmine_issue_datetime do
  desc 'Report issues whose stored times disagree with their start/due dates'
  task check: :environment do
    findings = RedmineIssueDatetime::DriftCheck.new.findings
    if findings.empty?
      puts 'No drift found.'
    else
      findings.each { |finding| puts finding.to_s }
      puts "#{findings.size} disagreement(s) found. " \
           'Run redmine_issue_datetime:repair to correct them.'
      # Non-zero so this is usable as a monitoring or CI check.
      exit 1
    end
  end

  desc 'Repair issues whose stored times disagree with their start/due dates'
  task repair: :environment do
    repaired = RedmineIssueDatetime::DriftCheck.new.repair!
    if repaired.empty?
      puts 'No drift found; nothing to repair.'
    else
      repaired.each { |finding| puts "repaired: #{finding}" }
      puts "#{repaired.size} disagreement(s) repaired."
    end
  end
end
