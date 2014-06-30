## Overview

A server library which will ease you life.

Now NoBone is based on express.js and some other useful libraries.

[![Build Status](https://travis-ci.org/ysmood/nobone.svg)](https://travis-ci.org/ysmood/nobone)


## Install

    npm install nobone


## Quick Start

```coffeescript
nb = require 'nobone'

port = 8013

# All modules use default options to init.
# If you want don't init a specific module,
# for example 'db' module, just exclude it:
#	nb.init {
#		renderer: null
#		service: null
#	}
nb.init {
	db: null
	renderer: { enable_watcher: true }
	service: null
}
# Print all available modules.
nb.available_modules().done (list) ->
	nb.kit.log 'available_modules'
	nb.kit.log list, 'inspect', { depth: 3, colors: true }

# Server
nb.service.get '/', (req, res) ->

	# Renderer
	# You can also render coffee, stylus, or define custom handlers.
	nb.renderer.render('test/sample.ejs')
	.done (tpl_func) ->
		res.send tpl_func({ auto_reload: nb.renderer.auto_reload() })

# Launch socket.io and express.js
# Launch only express.js: "nb.service.listen port"
nb.service.server.listen port

# Kit
# Print out time, log message, time span between two log.
nb.kit.log 'Listen port ' + port

# Static folder to automatically serve coffeescript and stylus.
nb.service.use nb.renderer.static({ root_dir: 'test' })

# Use socket.io to trigger reaload page.
# Edit the 'test/sample.ejs' file, the page should auto reload.
nb.renderer.on 'file_modified', (path) ->
	nb.service.io.emit 'file_modified', path

# Database
# Nobone has a build-in file database.
# For more info see: https://github.com/ysmood/jdb
# Here we save 'a' as value 1.
nb.db.exec({
	command: (jdb) ->
		jdb.doc.a = 1
		jdb.save('OK')
}).done (data) ->
	nb.kit.log data
```

Kit usage

```coffeescript
# Monitor app. Watch and restart app automatically.
# It's a light weight monitor, for server test.
# For further info see the 'Cakefile' of this project.
app_path = 'app.coffee'
nb.kit.monitor_app {
	bin: 'coffee'
	app: app_path
	watch_list: [app_path, 'lib/**/*.coffee']
}
```


## CLI

Install nobone globally: `npm install -g nobone`

```bash
# Help info
nobone -h

# Use it as a static file server for current directory.
nobone

# Use regex to filter the log info.
# Print out all the log if it contains '.ejs'
log_reg='.ejs' nobone

# Use custom logic to start up.
nobone app.js

```



## BSD

May 2014, Yad Smood
