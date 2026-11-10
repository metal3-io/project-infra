#! /usr/bin/env python3
# adapted from https://middlewaretechnologies.in/2022/03/how-to-extract-plugin-version-compatibility-details-with-jenkins.html
import sys
import requests
import click
import yaml
from bs4 import BeautifulSoup
from semver import Version as semver_version
from loguru import logger

def get_defaults(filename: str = 'roles/application/defaults/main.yaml') -> dict:
    logger.debug(f"reading file {filename}")
    with open(filename, 'r') as f:
        data = yaml.safe_load(f)
    return data or {}

def get_jenkins_version() -> str:
    defaults = get_defaults()
    image_name = defaults.get('config').get('images').get('jenkins')
    version = image_name.rsplit(':', maxsplit=2)[1].removesuffix('-lts@sha256')
    return version

def get_plugins(filename: str) -> dict:
    logger.debug(f"reading file {filename}")
    try:
        f = open(filename, 'r')
    except:
        logger.error(f"could not read {filename}")
        sys.exit(1)
    else:
        try:
            data = yaml.safe_load(f)
        finally:
            f.close()
    return data or {}

def update_plugins(plugins: dict, filename: str) -> None:
    logger.debug(f"writing file {filename}")
    try:
        f = open(filename, 'w')
    except:
        logger.error(f"could not write {filename}")
        sys.exit(1)
    else:
        try:
            f.write(yaml.safe_dump(plugins, explicit_start=True))
        finally:
            f.close()

def get_deps(plugin: str, deps: dict = {}) -> dict:
    if plugin not in deps:
        # unprocessed plugin
        logger.debug(f"finding dependencies of {plugin}")
        dep_url = f"https://plugins.jenkins.io/{plugin}/dependencies"
        raw_dep_page = requests.get(dep_url).text
        dep_page = BeautifulSoup(raw_dep_page, 'html.parser')
        title = dep_page.find('title')
        if not title or title.get_text() == 'Plugin page not found':
            logger.error(f"plugin {plugin} not found")
            return {}
        if _depmarker := dep_page.find('h2', string='Dependencies'):
            # plugin has dependencies
            deps[plugin] = []
            if independent := _depmarker.find_next_sibling('div', attrs={"class":"empty"}, string="No dependencies found"):
                logger.debug(f"plugin {plugin} has no dependencies")
            if not independent:
                if _opt := dep_page.find('h3', string='Optional'):
                    # plugin has optional dependencies
                    _optdeps = []
                    for _optdep in _opt.find_next_siblings('div'):
                        _name = _optdep.find('a').get('href').strip('/')
                        _optdeps.append(_name)
                    logger.debug(f"optional dependencies: {', '.join(_optdeps)}")
                _deps = dep_page.find_all('div', attrs={"class":"implied"})
                dep_names = [_dep.find_all('a')[0].get('href').strip('/') for _dep in _deps]
                if _opt:
                    # disregard optional dependencies
                    dep_names = list(set(dep_names).difference(_optdeps))
                logger.debug(f"dependencies: {', '.join(dep_names)}")
                deps[plugin] = dep_names
                for dep in dep_names:
                    get_deps(dep, deps)
    return deps

def get_plugin_version(plugin: str, jenkins_version: str) -> dict:
    logger.debug(f"finding latest version of {plugin} compatible with {jenkins_version}")
    plugin_url = f"https://updates.jenkins.io/download/plugins/{plugin}"
    raw_plugin_page = requests.get(plugin_url).text
    plugin_page = BeautifulSoup(raw_plugin_page, 'html.parser')
    if plugin_page.find('title').get_text() == '404 Not Found':
        logger.error(f"plugin {plugin} not found") # TODO: get_plugin_version() should not be invoked for plugins not found by get_deps(); try a single bogus name to see
        return {}
    versions = plugin_page.find_all('a', attrs={"class":"version"})[1:] # the first is "latest"
    checksums = plugin_page.find_all('div', attrs={"class":"checksums"})
    core_deps = [ d.get_text().split(' ')[-1] for d in plugin_page.find_all('div', attrs={"class":"core-dependency"}) ]
    padded_deps = [ d if semver_version.is_valid(d) else f"{d}.0" for d in core_deps ]
    compatible_versions = [ index for index, required_version in enumerate(padded_deps) if semver_version.parse(required_version) <= semver_version.parse(jenkins_version) ]
    if not compatible_versions:
        logger.warning(f"no version of {plugin} is compatible with {jenkins_version}")
        return {}
    newest_compatible_version = min(compatible_versions)
    version = versions[newest_compatible_version].get_text()
    checksum = checksums[newest_compatible_version * 2 + 1].get_text().lower().replace(' ', '').replace('-', '') # each version has two checksums, of which SHA-256 comes second
    return {'version': version, 'checksum': checksum}

@click.command()
@click.option("--debug", is_flag=True, default=False, help='print verbose debug messages')
@click.option("--allplugins", is_flag=True, default=False, help='update all plugins listed in the manifest')
@click.option("--nodeps", is_flag=True, default=False, help='do not resolve plugin dependencies recursively')
@click.option("--update", is_flag=True, default=False, help='allow updates to listed plugins')
@click.option("--pretend", is_flag=True, default=False, help='do not modify plugin manifest')
@click.option("--jenkins-version", default=get_jenkins_version, show_default=True, help='the semantic version number of Jenkins')
@click.option("--manifest", help='name of the manifest file')
@click.argument('plugins', nargs=-1)
def main(manifest: str, jenkins_version: str, plugins: str, debug: bool, allplugins: bool, nodeps: bool, update: bool, pretend: bool) -> None:
    """PLUGINS is a whitespace-separated list of plugin names."""
    if not debug:
        logger.remove()
        logger.add(sys.stdout, level="INFO")
    if ( plugins or nodeps or not update ) and allplugins:
        logger.error("--allplugins is mutually exclusive with --nodeps or a list of plugins passed as arguments, but requires --update")
        sys.exit(1)
    if not manifest:
        logger.error("a manifest file name is required")
        sys.exit(1)
    listed_plugins = get_plugins(manifest)
    if allplugins:
        plugins = listed_plugins.keys()

    deps, new_plugins, latest, all_plugins = {}, {}, None, []
    for plugin in set(plugins):
        if nodeps:
            all_plugins = plugins
        else:
            deps = get_deps(plugin)
            all_deps = list(set(sum(deps.values(), [])))
            all_deps.insert(0, plugin)
            logger.debug(f"all dependencies for {', '.join(sorted(plugins))}: {', '.join(sorted(all_deps))}")
            all_plugins.extend(all_deps)
    all_plugins = sorted(list(set(all_plugins)))
    for plugin in all_plugins:
        if plugin in listed_plugins:
            # already listed
            if not update:
                # leave it alone
                logger.debug(f"plugin {plugin} already listed and updates are disabled")
                continue
        # include its latest compatible version
        if ( latest := get_plugin_version(plugin, jenkins_version) ) != listed_plugins.get(plugin) and latest:
            new_plugins.update({plugin: latest})

    if not new_plugins and latest:
            # nothing to do
            logger.info(f"deps already listed for {', '.join(plugins)}")
            return
    listed_plugins.update(new_plugins)
    if new_plugins:
        logger.info("new: " + ', '.join([f"{item[0]}:{item[1]['version']}" for item in new_plugins.items()]))
    if pretend:
        return
    update_plugins(listed_plugins, manifest)

if __name__ == "__main__":
    main()
