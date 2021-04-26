config = {
	'name': 'open-graph-api',
	'rocketchat': {
		'channel': 'builds',
		'from_secret': 'private_rocketchat'
	},
	'branches': [
		'main'
	],
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
						'/usr/local/bin/docker-entrypoint.sh validate -i api/openapi-spec/v0.0.yml',
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