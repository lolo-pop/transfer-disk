# Copyright (C) 2011-2012 Red Hat Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

require 'rexml/document'
include REXML

require 'virt-p2v/blockdevice'

module VirtP2V


# name          User entry
# memory        Editable
# cpus          Editable
# arch          Detected: cpuflags contains lm (long mode)
# features      Detected: apic, acpi, pae
# disks         Editable, default to all
#   device        Detected
#   path          Detected
#   is_block      1
#   format        raw
# removables    Editable, default to all
#   device        Detected
#   type          Detected
# nics          Editable, default to all connected
#   mac           Detected, option to generate new
#   vnet          Set to nic name
#   vnet_type     bridge

class Converter
    attr_accessor :profile, :name, :cpus, :memory, :arch, :debug, :flag
    attr_reader :features, :disks

    attr_reader :connection

    def convert(status, progress, &completion)
        iterate(
            [
                lambda {|cb|
                    iterate(@disks.map {|dev|
                        lambda {|cb2|
                            disk(dev, status, progress, cb2)
                        }
                    }, cb)
                }
            ],
            completion
        )
    end
    def confirm_cancel(f)
         @flag = f
    end
    private

    def initialize
        @mutex = Mutex.new
        @profile = nil
        @debug = false
        @flag = false
        # destination which files are transferred to
        @dest = nil

        # Initialize basic system information
        @name = '' # There's no reasonable default for this

        # Initialise empty lists for optional devices. These will be added
        # according to the user's selection
        @disks = []
        @removables = []
        @nics = []

        @debug = false
    end
    
    def disk(dev, status, progress, completion)
        path = "/dev/#{dev}"
        size = FixedBlockDevice[dev].size
        status.call("正在迁移 #{dev}")
        iterate(
            [
                lambda { |cb|
                    # CORE function :)
                    run(cb) {
                        begin
                            `dd if=#{path} | gzip >#{name.gsub(/ /, '\\ ')}`
                            Gtk.queue {
                                if flag then  
                                    status.call("迁移已取消")
                                else
                                    status.call('迁移已完成')
                                end
                                cb.call(true)
                            }
                        rescue => e
                            cb.call(e)
                        end
                    }
                }
            ],
            completion
        )
        #status.call("迁移#{dev}已完成")
        
    end


    def iterate(stages, completion)
        i = 0
        cb = lambda { |result|
            if result.kind_of?(Exception) then
                completion.call(result)
            else
                i += 1
                if i == stages.length then
                    completion.call(true)
                else
                    stages[i].call(cb)
                end
            end
        }
        stages[0].call(cb)
    end

    def run(cb)
        # Run the given block in a new thread
        t = Thread.new {
            begin
                # We can't run more than 1 command simultaneously
                @mutex.synchronize { yield }
            rescue => ex
                # Deliver exceptions to the caller, then re-raise them
                Gtk.queue { cb.call(ex) }
                raise ex
            end
        }
    end

end
end
