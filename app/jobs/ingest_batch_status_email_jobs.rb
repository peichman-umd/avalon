# Copyright 2011-2017, The Trustees of Indiana University and Northwestern
#   University.  Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#   CONDITIONS OF ANY KIND, either express or implied. See the License for the
#   specific language governing permissions and limitations under the License.
# ---  END LICENSE_HEADER BLOCK  ---

# @since 6.3.0
# Scans all BatchRegistries to look for registries where all entries are complete or errored
# Sends an email to the user to alert them to this fact
class IngestFinished < ActiveJob::Base
  queue_as :ingest_finished_job
  def perform
    # Get all unlocked items that don't have an email sent for them and see if an email can be sent
    BatchRegistries.where(completed_email_sent: false, error_email_sent: false, locked: false).each do |br|
      # Get the entries for the batch and see if they all complete
      status = { complete: true, errors: false }
      BatchEntries.where(batch_registries_id: br.id).each do |entry|
        status[complete] = false unless entry.complete || entry.error
        status[errors] = true if entry.error
      end

      next unless status[complete]
      unless status[errors]
        BatchRegistriesMailer.batch_registration_finished_mailer(br).deliver_now
        entry.completed_email_sent = true
        entry.complete = true
      end
      if status [errors]
        BatchRegistriesMailer.batch_registration_finished_mailer(br).deliver_now
        entry.error_email_sent = true
        entry.error = true
      end
      entry.save
    end
  end
end

# @since 6.3.0
# Scans all batch registries that are not completed and determines if that have been
# sitting for an inordinate amount of time, alerts the admin user if this is the case
class StalledJob < ActiveJob::Base
  queue_as :ingest_status_job
  def perform
    stall_time = 4.days
    # Get every batch registry not marked as complete
    BatchRegistries.where(completed_email_sent: false, error_email_sent: false).each do |br|
      batch_stalled = false
      batch_stalled = true if br.locked && Time.now.utc - br.updated_at > stall_time
      unless batch_stalled
        BatchEntries.where(batch_registries_id: br.id, error: false, complete: false).each do |be|
          batch_stalled = true if Time.now.utc - be.updated_at > stall_time
          break if batch_stalled
        end
      end
      BatchRegistriesMailer.batch_registration_stalled_mailer(br) if batch_stalled
    end
  end
end
