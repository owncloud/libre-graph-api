config = {
	'name': 'open-graph-api',
	'rocketchat': {
		'channel': 'builds',
		'from_secret': 'private_rocketchat'
	},
	'branches': [
		'main'
	],
	'languages': {
		'go': {
			'src': "out-go",
			'repo-slug': "open-graph-api-go",
			'branch': 'main',
		},
	},
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
	return linting(ctx) + generate(ctx, "go")

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
					'image': 'openapitools/openapi-generator-cli',
					'pull': 'always',
					'commands': [
						'/usr/local/bin/docker-entrypoint.sh validate -i api/openapi-spec/v0.0.yaml',
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
		'name': 'generate',
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
			{
				"name": "clean-%s" % lang,
				"image": "owncloudci/alpine:latest",
				"commands": [
					"rm -rf %s/*" % config["languages"][lang]["src"],
				],
			},
			{
				'name': 'generate-%s' % lang,
				'image': 'openapitools/openapi-generator-cli',
				'pull': 'always',
				'commands': [
					'/usr/local/bin/docker-entrypoint.sh generate -i api/openapi-spec/v0.0.yaml --additional-properties=packageName=opengraph --git-user-id=owncloud --git-repo-id=%s -g %s -o %s' % (config["languages"][lang]["repo-slug"], lang, config["languages"][lang]["src"]),
				],
			},
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
					"author_email": "michael.barz@zeitgestalten.eu", 
					"author_name": "micbar",
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
			},
		],
		'depends_on': [],
		'trigger': {
			'ref': [
				'refs/tags/**'
			]
		}
	}

	for branch in config['branches']:
		result['trigger']['ref'].append('refs/heads/%s' % branch)

	pipelines.append(result)

	return pipelines
