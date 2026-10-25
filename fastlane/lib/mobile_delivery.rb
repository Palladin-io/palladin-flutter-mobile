module MobileDelivery
  class Failure < StandardError; end

  def self.deliver(store, attempts: 80, pause: -> { sleep 30 })
    uploaded = false
    attempts.times do
      case store.state
      when :distributed then return 'distributed'
      when :superseded then return 'superseded'
      when :absent
        raise Failure, 'Upload acceptance is unresolved; reconcile the original attempt before retrying' if uploaded
        store.upload
        uploaded = true
      when :processing, :uncertain
        # Poll the exact reserved build; never repeat its upload after an ambiguous response.
      else
        raise Failure, 'Store provisioning, identity or processing check failed'
      end
      pause.call
    end
    raise Failure, 'Store processing/distribution timed out; resume the original release'
  end
end
