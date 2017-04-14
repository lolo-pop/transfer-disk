require 'gtk2'
require 'virt-p2v/gtk-queue'

module VirtP2V
module UI

class Main
    def get_object(name)
        o = @builder.get_object(name)
        #raise "Object #{name} not found in ui" unless o != nil

        return o
    end

    def show

        @builder.connect_signals { |signal|
            #raise "No hander for signal #{signal}" \
            #    unless @signal_handlers.has_key?(signal)

            @signal_handlers[signal]
        }

        # Display the main window
        main = self.get_object('main_window')
        main.show_all()

        # Explicitly set a cursor
        # This doesn't seem to happen automatically when the client is started
        # from xinit, leaving the user with no visible cursor.
        main.window.cursor = Gdk::Cursor.new(Gdk::Cursor::Type::X_CURSOR)
    end

    def register_handler(signal, handler)
        @signal_handlers[signal] = handler
    end

    def main_loop
        Gtk.main_with_queue 100
    end

    def active_page=(name)
        raise "Attempt to activate non-existent page #{name}" \
            unless @pages.has_key?(name)

        page = @pages[name]

        @page_vbox = self.get_object('page_vbox') unless defined? @page_vbox
        @page_vbox.remove(@selected) if defined? @selected
        @page_vbox.add(page)
        @selected = page
    end

    def active_page
        return @selected
    end

    def quit
        Gtk.main_quit()
    end

    private

    def initialize
        @builder = Gtk::Builder.new()

        # Find the UI definition in $LOAD_PATH
        i = $LOAD_PATH.index { |path|
            File.exists?(path + '/virt-p2v/ui/p2v.ui')
        }
        @builder.add_from_file($LOAD_PATH[i] + '/virt-p2v/ui/p2v.ui')

        @signal_handlers = {}
        self.register_handler('gtk_main_quit', method(:quit))

        # Configure the Wizard page frame
        # Can't change these colours from glade for some reason
        self.get_object('title_background').
           modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#86ABD9'))
        self.get_object('page_frame').
           modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#86ABD9'))

        # Load all pages from glade
        @pages = {}
        [ #'network_win', 'server_win',
          'conversion_win'].each { |name|
            page = self.get_object(name)
            puts(page.children)

            child = page.children[0]
            page.remove(child)
            @pages[name] = child
        }

        # Set a default first page
        self.active_page = 'conversion_win'
    end
end

end # UI
end 
