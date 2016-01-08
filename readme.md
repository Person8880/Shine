## Shine

An administration mod for Natural Selection 2.

The design goals are:
- Be easy to extend and maintain.
- Be easy for admins to use.
- Be completely modular, everything is optional.

## Latest changes

The latest changes [can be found here](https://github.com/Person8880/Shine/wiki/Changelog).

## Pull requests

If you wish to help out, feel free to send pull requests. Please [see the style guidelines here](https://github.com/Person8880/Shine/wiki/Pull-Requests) and make sure you are merging into the **develop** branch, not master.

## Configuration

The mod will create its configuration files in `config://shine`.

The base config file will be called `BaseConfig.json` and will determine base settings and which plugins to load. Plugins will create their configs inside `config://shine/plugins` by default, you may change this if you wish in `BaseConfig.json`.

## User data

User data will be loaded locally by default, from the file `config://shine/UserConfig.json`. On first run a sample file will be created. If you set 'GetUsersFromWeb' to true and provide a correct URL to a JSON file in 'UsersURL', Shine will load its users from there instead.

## Further documentation

Further documentation is [available at the wiki](https://github.com/Person8880/Shine/wiki) including default config files for each plugin and for the base config.
