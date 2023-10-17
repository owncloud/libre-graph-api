config = {
	'name': 'libre-graph-api',
	'rocketchat': {
		'channel': 'builds',
		'from_secret': 'rocketchat_chat_webhook'
	},
	'branches': [
		'main'
	],
	'languages': {
		'go': {
			'src': "out-go",
			'repo-slug': "libre-graph-api-go",
			'branch': 'main',
		},
		'typescript-axios': {
			'src': "out-typescript-axios",
			'repo-slug': "libre-graph-api-typescript-axios",
			'branch': 'main',
		},
		'cpp-qt-client': {
			'src': "out-cpp-qt-client",
			'repo-slug': "libre-graph-api-cpp-qt-client",
			'branch': 'main',
		},
		'php': {
			'src': "out-php",
			'repo-slug': "libre-graph-api-php",
			'branch': 'main',
		},
	},
	'openapi-generator-image': 'openapitools/openapi-generator-cli:v7.0.1@sha256:1894bae95de139bd81b6fc2ba8d2e423a2bf1b0266518d175bd26218fe42a89b'
}

def main(ctx):
	stages = stagePipelines(ctx)
	if (stages == False):
		print('Errors detected. Review messages above.')
		return []

	after = afterPipelines(ctx)
	dependsOn(stages, after)
	return stages + after

def stagePipelines(ctx):
	linters = linting(ctx)
	generators = generate(ctx, "go") + generate(ctx, "typescript-axios") + generate(ctx, "cpp-qt-client") + generate(ctx, "php")
	dependsOn(linters, generators)
	return linters + generators

def afterPipelines(ctx):
	return [
		notify()
	]

def dependsOn(earlierStages, nextStages):
	for earlierStage in earlierStages:
		for nextStage in nextStages:
			nextStage['depends_on'].append(earlierStage['name'])

def notify():
	result = {
		'kind': 'pipeline',
		'type': 'docker',
		'name': 'chat-notifications',
		'clone': {
			'disable': True
		},
		'steps': [
			{
				'name': 'notify-rocketchat',
				'image': 'plugins/slack:1',
				'pull': 'always',
				'settings': {
					'webhook': {
						'from_secret': config['rocketchat']['from_secret']
					},
					'channel': config['rocketchat']['channel']
				}
			}
		],
		'depends_on': [],
		'trigger': {
			'ref': [
				'refs/tags/**'
			],
			'status': [
				'success',
				'failure'
			]
		}
	}

	for branch in config['branches']:
		result['trigger']['ref'].append('refs/heads/%s' % branch)

	return result

def linting(ctx):
	pipelines = []

	result = {
			'kind': 'pipeline',
			'type': 'docker',
			'name': 'lint',
			'steps': [
				{
					'name': 'validate',
					'image': config['openapi-generator-image'],
					'pull': 'always',
					'commands': [
						'/usr/local/bin/docker-entrypoint.sh validate -i api/openapi-spec/v1.0.yaml',
					],
				}
			],
			'depends_on': [],
			'trigger': {
				'ref': [
					'refs/pull/**',
					'refs/tags/**'
				]
			}
		}

	for branch in config['branches']:
		result['trigger']['ref'].append('refs/heads/%s' % branch)

	pipelines.append(result)

	return pipelines

def generate(ctx, lang):
	pipelines = []
	result = {
		'kind': 'pipeline',
		'type': 'docker',
		'name': 'generate-%s' % lang,
		'steps': [
			{
				"name": "clone-remote-%s" % lang,
				"image": "plugins/git-action:1",
				"pull": "always",
				"settings": {
					"actions": [
						"clone",
					],
					"remote": "https://github.com/owncloud/%s" % config["languages"][lang]["repo-slug"],
					"branch": "%s" % config["languages"][lang]["branch"],
					"path": "%s" % config["languages"][lang]["src"],
					"netrc_machine": "github.com",
					"netrc_username": {
						"from_secret": "github_username",
					},
					"netrc_password": {
						"from_secret": "github_token",
					},
				},
			},
			] + lint(lang) + [
			{
				'name': 'generate-%s' % lang,
				'image': getGeneratorImageVersion(lang),
				'pull': 'always',
				'commands': [
					'test -d "templates/{0}" && TEMPLATE_ARG="-t templates/{0}" || TEMPLATE_ARG=""'.format(lang),
					'rm -Rf %s/*' % config["languages"][lang]["src"],
					'/usr/local/bin/docker-entrypoint.sh generate --enable-post-process-file -i api/openapi-spec/v1.0.yaml $${TEMPLATE_ARG} --additional-properties=packageName=libregraph --git-user-id=owncloud --git-repo-id=%s -g %s -o %s' % (config["languages"][lang]["repo-slug"], lang, config["languages"][lang]["src"]),
					'cp LICENSE %s/LICENSE' % config["languages"][lang]["src"],
				],
			}
			] + validate(lang) + [
			{
				"name": "diff",
				"image": "owncloudci/alpine:latest",
				"commands": [
					"cd %s" % config["languages"][lang]["src"],
					"git diff",
				],
			},
			{
				"name": "publish-%s" % lang,
				"image": "plugins/git-action:1",
				"settings": {
					"actions": [
						"commit",
						"push",
					],
					"message": "%s" % ctx.build.message,
					"branch": "%s" % config["languages"][lang]["branch"],
					"path": "%s" % config["languages"][lang]["src"],
					"author_email": "%s" % ctx.build.author_email,
					"author_name": "%s" % ctx.build.author_name,
					"followtags": True,
					"remote" : "https://github.com/owncloud/%s" % config["languages"][lang]["repo-slug"],
					"netrc_machine": "github.com",
					"netrc_username": {
						"from_secret": "github_username",
					},
					"netrc_password": {
						"from_secret": "github_token",
					},
				},
				"when": {
					"ref": {
						"exclude": [
							"refs/pull/**",
						],
					},
				},
			}],
		'depends_on': [],
		'trigger': {
			'ref': [
				'refs/tags/**',
				'refs/pull/**',
			]
		}
	}

	for branch in config['branches']:
		result['trigger']['ref'].append('refs/heads/%s' % branch)

	pipelines.append(result)

	return pipelines

def validate(lang):
	steps = {
		"cpp-qt-client": [
			{
				"name": "validate-cpp",
				"image": "owncloudci/client",
				"commands": [
					"mkdir build-qt",
					"cd build-qt",
					"cmake -GNinja -S ../%s/client" % config["languages"][lang]["src"],
					"ninja",
					"cd ..",
					"rm -Rf build-qt",
				]
			}
		],
		"go": [
			{
				"name": "go-fmt",
				"image": "owncloudci/golang:1.18",
				"commands": [
					"cd %s" % config["languages"][lang]["src"],
					"gofmt -w .",
				]
			},
			{
				"name": "go-mod",
				"image": "owncloudci/golang:1.18",
				"commands": [
					"cd %s" % config["languages"][lang]["src"],
					"go mod tidy",
				]
			},
			{
				"name": "validate-go",
				"image": "golangci/golangci-lint:latest",
				"commands": [
					"cd %s" % config["languages"][lang]["src"],
					"golangci-lint run -v",
				]
			},
		],
		"php": [
			{
				"name": "validate-php",
				"image": "owncloudci/php:8.0",
				"commands": [
					"composer install",
					"vendor/bin/parallel-lint %s" % config["languages"][lang]["src"],
				]
			},
		],
		"typescript-axios": []
	}

	return steps[lang]

def lint(lang):
	if "openapi-generator-image" in config["languages"][lang]:
		# there is a specific openapi-generator-image to use for this language, so validate the yaml spec using that image
		return [
			{
				'name': 'lint',
				'image': config["languages"][lang]["openapi-generator-image"],
				'pull': 'always',
				'commands': [
					'/usr/local/bin/docker-entrypoint.sh validate -i api/openapi-spec/v1.0.yaml',
				],
			}
		]

	return []

def getGeneratorImageVersion(lang):
	if "openapi-generator-image" in config["languages"][lang]:
		return config["languages"][lang]["openapi-generator-image"]
	return config["openapi-generator-image"]
