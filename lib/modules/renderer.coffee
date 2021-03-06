_ = require 'lodash'
Q = require 'q'
kit = require '../kit'
express = require 'express'
{ EventEmitter } = require 'events'

###*
 * A abstract renderer for any string resources, such as template, source code, etc.
 * It automatically uses high performance memory cache.
 * You can run the benchmark to see the what differences it makes.
 * Even for huge project its memory usage is negligible.
 * @param  {object} opts Defaults:
 * {
 * 	enable_watcher: process.env.NODE_ENV == 'development'
 * 	code_handlers: {
 * 		'.js': {
 * 			ext_src: '.coffee'
 * 			compiler: (str) ->
 * 				coffee = require 'coffee-script'
 * 				coffee.compile(str, { bare: true })
 * 		}
 * 		'.css': {
 * 			ext_src: '.styl'
 * 			compiler: (str, path) ->
 * 				stylus = require 'stylus'
 * 				stylus_render = Q.denodeify stylus.render
 * 				stylus_render(str, { filename: path })
 * 		}
 * 		'.ejs': {
 * 			default: true    # Whether it is a default handler
 * 			ext_src: '.ejs'
 * 			type: 'html'
 * 			compiler: (str, path) ->
 * 				ejs = require 'ejs'
 * 				tpl = ejs.compile str, { filename: path }
 *
 * 				(data = {}) ->
 * 					_.defaults data, { _ }
 * 					tpl data
 * 		}
 * 	}
 * }
 * @return {renderer}
###
module.exports = (opts) -> new Renderer(opts)

module.exports.defaults = {
	enable_watcher: process.env.NODE_ENV == 'development'
	code_handlers: {
		'.js': {
			ext_src: '.coffee'
			###*
			 * The compiler should fulfil two interface.
			 * It should return a promise object. Only handles string.
			 * @param  {string} str Source code.
			 * @param  {string} path For debug info.
			 * @return {promise} Contains the compiled code.
			###
			compiler: (str, path) ->
				coffee = require 'coffee-script'
				coffee.compile(str, { bare: true })
		}
		'.css': {
			ext_src: '.styl'
			compiler: (str, path) ->
				stylus = require 'stylus'
				stylus_render = Q.denodeify stylus.render
				stylus_render(str, { filename: path })
		}
		'.ejs': {
			default: true    # Whether it is a default handler
			ext_src: '.ejs'
			type: 'html'
			compiler: (str, path) ->
				ejs = require 'ejs'
				tpl = ejs.compile str, { filename: path }

				(data = {}) ->
					_.defaults data, { _ }
					tpl data
		}
	}
}


class Renderer extends EventEmitter then constructor: (opts = {}) ->

	super

	_.defaults opts, module.exports.defaults

	self = @

	self.code_handlers = opts.code_handlers

	cache_pool = {}

	###*
	 * Set a static directory.
	 * Static folder to automatically serve coffeescript and stylus.
	 * @param  {object} Defaults: { root_dir: '.' }
	 * @return {middleware} Experss.js middleware.
	###
	self.static = (opts = {}) ->
		_.defaults opts, {
			root_dir: '.'
		}

		static_handler = express.static opts.root_dir

		return (req, res, next) ->
			path = kit.path.join opts.root_dir, req.path

			# Try to send the bin file first.
			static_handler req, res, ->
				handler = get_handler path
				if handler
					get_cached(handler)
					.then (code) ->
						switch typeof code
							when 'string'
								res.type handler.type or handler.ext_bin
								res.send code

							when 'function'
								res.type handler.type or 'html'
								res.send code()

							else
								throw new Erorr('unknown_code_type')

					.catch (err) ->
						if err.code == 'ENOENT'
							next()
						else
							if self.listeners('compile_error').length == 0
								kit.log err.toString().red, 'error'
							else
								self.emit 'compile_error', path, code
							res.send 500, 'compile_error'
				else
					next()

	###*
	 * Render a file. It will auto detect the file extension and
	 * choose the right compiler to handle the code.
	 * @param  {string} path The file path
	 * @return {promise} Contains the compiled code.
	###
	self.render = (path) ->
		handler = get_handler path, true
		get_cached handler

	###*
	 * The browser javascript to support the auto page reload.
	 * You can use the socket.io event to custom you own.
	 * @return {string} Returns html.
	###
	self.auto_reload = ->
		'''
			<!-- Auto reload page helper. -->
			<script type="text/javascript">
				if (!window.io) {
					document.write(unescape('%3Cscript%20src%3D%22/socket.io/socket.io.js%22%3E%3C/script%3E'));
				}
			</script>
			<script type="text/javascript">
				(function () {
					var sock = io();
					sock.on('file_modified', function (data) {
						console.log(">> Reload: " + data);
						location.reload();
					});
				})();
			</script>
		'''

	###*
	 * Release the resources.
	###
	self.close = ->
		fs = require 'fs'
		for k, v of cache_pool
			fs.unwatchFile(k)

	get_code = (handler) ->
		path = handler.pathless + handler.ext_src

		kit.readFile(path, 'utf8')
		.then (str) ->
			handler.compiler(str, path)
		.then (code) ->
			cache_pool[path] = code

	get_cached = (handler) ->
		path = null
		handler.compiler ?= (str) -> str

		path = handler.pathless + handler.ext_src

		if cache_pool[path] != undefined
			Q cache_pool[path]
		else
			get_code(handler)
			.then (code) ->
				if opts.enable_watcher
					self.emit 'watch_file', path
					kit.watch_file path, (path, curr, prev) ->
						if curr.mtime != prev.mtime
							self.emit 'file_modified', path
							get_code(handler)

				return code

	get_handler = (path, is_direct = false) ->
		ext_bin = kit.path.extname path

		if is_direct
			handler = _.find self.code_handlers, (el) -> el.ext_src == ext_bin
		else if ext_bin == ''
			handler = _.find self.code_handlers, (el) -> el.default
		else
			handler = self.code_handlers[ext_bin]

		if handler
			handler = _.clone(handler)
			handler.ext_bin = ext_bin
			handler.pathless = kit.path.join(
				kit.path.dirname(path)
				kit.path.basename(path, ext_bin)
			)
			handler
		else
			null
