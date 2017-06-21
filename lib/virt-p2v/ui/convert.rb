require 'gtk2'

require 'virt-p2v/blockdevice'
require 'virt-p2v/gtk-queue'

module VirtP2V::UI::Convert


    CONVERT_NETWORK_CONVERT = 0
    CONVERT_NETWORK_DEVICE  = 1

    CONVERT_FIXED_CONVERT   = 0
    CONVERT_FIXED_DEVICE    = 1
    CONVERT_FIXED_PROGRESS  = 2
    CONVERT_FIXED_SIZE_GB   = 3

    CONVERT_REMOVABLE_CONVERT   = 0
    CONVERT_REMOVABLE_DEVICE    = 1
    CONVERT_REMOVABLE_TYPE      = 2

    UI_STATE_INVALID    = 0
    UI_STATE_VALID      = 1
    UI_STATE_CONNECTING = 2
    UI_STATE_CONVERTING = 3
    UI_STATE_COMPLETE   = 4

    EV_VALID        = 0
    EV_BUTTON       = 1
    EV_CONNECTION   = 2
    EV_CONVERTED    = 3
       
    def self.init(ui, converter)
        # ListStores
        @fixeds     = ui.get_object('convert_fixed_list')

        # Widgets
        @name       = ui.get_object('convert_name')
        @editable   = ui.get_object('convert_editable')
        @button     = ui.get_object('convert_button')
        @status     = ui.get_object('convert_status')
        @path       = ui.get_object('convert_path')
        @cancel     = ui.get_object('cancel_button')
        @clean      = ui.get_object('clean_button')
        @exit       = ui.get_object('exit_button')
        # Get initial values from converter
        @filename = nil
        @name.text = @filename
        
        VirtP2V::FixedBlockDevice.all_devices.each { |dev|
            fixed = @fixeds.append
            fixed[CONVERT_FIXED_CONVERT]    = true
            fixed[CONVERT_FIXED_DEVICE]     = dev.device
            fixed[CONVERT_FIXED_PROGRESS]   = 0
            fixed[CONVERT_FIXED_SIZE_GB]    = dev.size / 1024 / 1024 / 1024
        }

        # Event handlers   
        ui.register_handler('convert_name_changed',
                            method(:update_values))
        ui.register_handler('convert_fixed_list_row_changed',
                            method(:convert_fixed_list_row_changed))
        ui.register_handler('convert_removable_list_row_changed',
                            method(:update_values))
        ui.register_handler('convert_network_list_row_changed',
                            method(:update_values))
        ui.register_handler('convert_fixed_select_toggled',
                            method(:convert_fixed_select_toggled))
        ui.register_handler('convert_button_clicked',
                            method(:convert_button_clicked))
        ui.register_handler('convert_path_clicked',
                            method(:convert_path_clicked))
        ui.register_handler('cancel_button_clicked',
                            method(:cancel_button_clicked))
        ui.register_handler('clean_button_clicked',
                            method(:clean_button_clicked))
	ui.register_handler('exit_button_clicked',
                            method(:exit_button_clicked))

        @state = nil
        set_state(UI_STATE_VALID)
        update_values
        update_path
        @ui = ui
        @converter = converter
    end

    def self.event(event, status)
    #convert
        case @state
        when UI_STATE_INVALID
            case event
            
            when EV_VALID
                set_state(UI_STATE_VALID) if status
            else
                #raise "Unexpected event: #{@state} #{event}"
            end
        when UI_STATE_VALID
            case event
            when EV_VALID
                set_state(UI_STATE_INVALID) if !status
            when EV_BUTTON
                set_state(UI_STATE_CONVERTING)
                convert

            else
                #raise "Unexpected event: #{@state} #{event}"

            end

        when UI_STATE_CONVERTING
            case event
            when EV_CONVERTED
                if status then
                    set_state(UI_STATE_COMPLETE)
                else
                    set_state(UI_STATE_VALID)
                end
            when EV_VALID
                # update_values will be called when the list stores are updated.
                # Untidy, but ignore it
            else
                #raise "Unexpected event: #{@state} #{event}"
            end
        else
            #raise "Unexpected UI state: #{@state}"
        end
    end
    def self.update_path
        @name.text = @filename
    end
    def self.set_state(state)
        # Don't do anything if state hasn't changed
        return if state == @state
        @state = state

        case @state
        when UI_STATE_INVALID
            @editable.sensitive = true
            @button.sensitive = false
        when UI_STATE_VALID
            @editable.sensitive = true
            @button.sensitive = true
        when UI_STATE_CONNECTING
            @editable.sensitive = false
            @button.sensitive = false
        when UI_STATE_CONVERTING
            @editable.sensitive = false
            @button.sensitive = false
        when UI_STATE_COMPLETE
            @editable.sensitive = true
            @button.sensitive = true

            # ... then leave this one as we hope to find it if we come back here
            set_state(UI_STATE_VALID)
        end
    end
    def self.convert
        @converter.convert(
            # status
            lambda { |msg|
                @status.text = msg
            },
            # progress
            lambda { |dev, progress|
                @fixeds.each { |model, path, iter|
                    next unless iter[CONVERT_FIXED_DEVICE] == dev

                   iter[CONVERT_FIXED_PROGRESS] = progress
                   break
               }
            }
        ) { |result|

            # N.B. Explicit test against true is required here, as result may be
            # an Exception, which would also return true if evaluated alone
            if result == true then
                event(EV_CONVERTED, true)
            else
                @status.text= '迁移已取消'
                event(EV_CONVERTED, true)
            end
          }
    end
    def self.cancel
        output = `ps -aux|grep dd\\ if=/dev/`
        res = output.split
        killed = res[1].to_i + 1
        begin
            `kill -9 #{res[1].to_i}`
            `kill -9 #{killed}`
            #`rm -f #{@filename.gsub(/ /, '\\ ')}` 
        end
        flag = 1
        @converter.confirm_cancel(flag)
    end
    def self.clean
        begin
	    if @filename == nil then 
		#:p @filename
	    else
                `rm -f #{@filename.gsub(/ /, '\\ ')}`
	    end 
	    #Gtk.queue {
	    #    status.call('清除已成功')
            #}
	    @status.text = '清除已成功'
        end
	#status.call('清除已成功')
        flag = 2
        @converter.confirm_clean(flag)
    end
    def self.exit
        begin
            exit!
        end
        #status.call('清除已成功')
        #flag = 2
        #@converter.confirm_clean(flag)
    end

    def self.convert_fixed_list_row_changed(model, path, iter)
        update_values
    end

    class InvalidUIState < StandardError; end

    def self.update_values
        valid = nil
        begin
            # Check there's a name set
            name = @filename
            raise InvalidUIState if name.nil? || name.strip.length == 0
            @converter.name = name
            # Check that at least 1 fixed storage device is selected
            fixed = false
            @converter.disks.clear
            @fixeds.each { |model, path, iter|
                if iter[CONVERT_FIXED_CONVERT] then
                    fixed = true
                    @converter.disks << iter[CONVERT_FIXED_DEVICE]
                end
            }
            raise InvalidUIState unless fixed

        rescue InvalidUIState
            valid = false
        end
        valid = true
        event(EV_VALID, valid)
        
    end

    def self.valid?
        # Check there's a profile selected
        #profile = @profile.active_iter
        #return false if profile.nil?

        # Check there's a name set
        name = @name.text
        return false if name.nil?
        return false unless name.strip.length > 0
=begin
        # Check cpus and memory are set and numeric
        cpus = @cpus.text
        return false if cpus.nil?
        cpus = Integer(cpus) rescue nil
        return false if cpus.nil?

        memory = @memory.text
        return false if memory.nil?
        memory = Integer(memory) rescue nil
        return false if memory.nil?
=end
        # Check that at least 1 fixed storage device is selected
        fixed = false
        @fixeds.each { |model, path, iter|
            if iter[CONVERT_FIXED_CONVERT] then
                fixed = true
                break
            end
        
        }
        return false unless fixed

        return true
    end

    def self.check_numeric(widget)
        value = widget.text
        if value.nil? ? false : begin
            value = Integer(value)
            value > 0
        rescue
            false
        end
        then
            widget.secondary_icon_name = nil
        else
            widget.secondary_icon_name = 'gtk-dialog-warning'
            widget.secondary_icon_tooltip_text =
                'Value must be an integer greater than 0'
        end

        update_values
    end

    def self.convert_fixed_select_toggled(widget, path)
        iter = @fixeds.get_iter(path)
        iter[CONVERT_FIXED_CONVERT] = !iter[CONVERT_FIXED_CONVERT]
    end

    def self.convert_button_clicked
        event(EV_BUTTON, true)
        
    end

    def self.convert_path_clicked 
        dialog = Gtk::FileChooserDialog.new("Save File",
                                     nil,
                                     Gtk::FileChooser::ACTION_SAVE,
                                     nil,
                                     [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL],
                                     [Gtk::Stock::SAVE, Gtk::Dialog::RESPONSE_ACCEPT])


        if dialog.run == Gtk::Dialog::RESPONSE_ACCEPT
            @filename = dialog.filename
        end
        dialog.destroy
        update_path
    end

    def self.convert_name_changed
        @name.text = @filename
    end
    def self.cancel_button_clicked
        cancel
    end
    def self.clean_button_clicked
        clean
    end
    def self.exit_button_clicked
        exit
    end


end # module
