'use strict'

sysPath = require 'path'
fs = require 'fs-mode'
each = require 'async-each'

defaultSettings = (extname) ->
	switch extname
		when 'jade'
			regexp: /^\s*(?:include|extends)\s+(.+)/
		when 'styl'
			regexp: /^\s*(?:@import|@require)\s*['"]?([^'"]+)['"]?/
			exclusion: 'nib'
		when 'less'
			regexp: /^\s*@import\s*(?:\(\w+\)\s*)?['"]([^'"]+)['"]/
		when 'scss', 'sass'
			regexp: /^\s*@import\s*['"]?([^'"]+)['"]?/
			prefix: '_'
			exclusion: /^compass/
			extensionsList: ['scss', 'sass']
			multipass: [
				/@import[^;]+;/g
				/\s*['"][^'"]+['"]\s*,?/g
				/(?:['"])([^'"]+)/
			]

progenyConstructor = (mode, settings = {}) ->
	{
		rootPath
		extension
		regexp
		prefix
		exclusion
		extensionsList
		multipass
	} = settings
	parseDeps = (path, source, depsList, callback) ->
		parent = sysPath.dirname path if path

		mdeps = multipass?[..-2]
			.reduce (vals, regex) ->
				vals
					?.map (val) -> val.match regex
					.reduce (flat, val) -> flat.concat val
					, []
			, [source]
			?.map (val) -> (val.match multipass[multipass.length-1])[1]

		deps = source
			.toString()
			.split('\n')
			.map (line) ->
				line.match regexp
			.filter (match) ->
				match?.length > 0
			.map (match) ->
				match[1]
			.concat mdeps or []
			.filter (path) ->
				if '[object Array]' isnt toString.call exclusion
					exclusion = [exclusion]
				!!path and not exclusion.some (_exclusion) -> switch
					when _exclusion instanceof RegExp
						_exclusion.test path
					when '[object String]' is toString.call _exclusion
						_exclusion is path
					else false
			.map (path) ->
				if extension and '' is sysPath.extname path
					"#{path}.#{extension}"
				else
					path
			.map (path) ->
				if path[0] is '/' or not parent
					sysPath.join rootPath, path[1..]
				else
					sysPath.join parent, path

		if extension
			deps.forEach (path) ->
				if ".#{extension}" isnt sysPath.extname path
					deps.push "#{path}.#{extension}"

		if prefix?
			prefixed = []
			deps.forEach (path) ->
				dir = sysPath.dirname path
				file = sysPath.basename path
				if 0 isnt file.indexOf prefix
					prefixed.push sysPath.join dir, "#{prefix}#{file}"
			deps = deps.concat prefixed

		if extensionsList.length
			altExts = []
			deps.forEach (path) ->
				dir = sysPath.dirname path
				extensionsList.forEach (ext) ->
					if ".#{ext}" isnt sysPath.extname path
						base = sysPath.basename path, ".#{extension}"
						altExts.push sysPath.join dir, "#{base}.#{ext}"
			deps = deps.concat altExts

		if deps.length
			each deps, (path, callback) ->
				if path in depsList
					callback()
				else
					depsList.push path
					fs[mode].readFile path, encoding: 'utf8', (err, source) ->
						return callback() if err
						parseDeps path, source, depsList, callback
			, callback
		else
			callback()

	progeny = (path, source, callback) ->
		if typeof source is 'function'
			callback = source
			source = undefined

		fileExt = sysPath.extname(path)[1..]
		if path and source
			altExt = sysPath.extname(source)
			if not (0 < fileExt.length < 5) and 1 < altExt.length < 6
				tempPath = source
				source = path
				path = tempPath
				fileExt = altExt[1..]

		depsList = []

		extension ?= fileExt
		def = defaultSettings extension
		regexp ?= def.regexp
		prefix ?= def.prefix
		exclusion ?= def.exclusion
		extensionsList ?= def.extensionsList or []
		multipass ?= def.multipass

		run = ->
			parseDeps path, source, depsList, ->
				callback null, depsList
		if source?
			do run
		else
			fs[mode].readFile path, encoding: 'utf8', (err, fileContents) ->
				return callback err if err
				source = fileContents
				do run

	progenySync = (path, source) ->
		result = []
		progeny path, source, (err, depsList) ->
			throw err if err
			result = depsList
		result

	if mode is 'Sync' then progenySync else progeny

module.exports = progenyConstructor.bind null, 'Async'
module.exports.Sync = progenyConstructor.bind null, 'Sync'

