---
layout: post
---

Uploading Windows Binaries to PyPi
==================================

As the maintainer of [the Couchbase Python Client](https://github.com/couchbase/couchbase-python-client),
part of the release cycle is making Windows binaries available on PyPi.

Aside from actually building these binaries on Windows (we use MSVC
and Jenkins), they actually need to be uploaded to [PyPi](http://pypi.python.org/pypi/couchbase).

The way our binaries were built is as follows:

* We have a [Jenkins job](http://sdkbuilds.couchbase.com/job/pycbc-win)
configured to poll for an SCM change
* When an SCM change happens, the Jenkins builder downloads
the change and builds it.
* Once built, they are uploaded to an [S3 snapshot bucket](http://packages.couchbase.com/clients/python/snapshots).


This process worked fairly well until I had to upload 10+ binaries to
PyPi.

As any good developer would do, I refused to do this by hand - there had
to be a better way to automate this. However, I could not find any solutions
for this, and the single post I found a google which actually dealt with it
was [rather depressing](http://as.ynchrono.us/2011/09/releasing-python-software-is-tedious.html)


The common way to upload things to PyPi is by using the `setup.py sdist upload`
command or similar. In this case, it will "magically" make a source distribution
and upload it for you. Though this is kind of messed up too -- apparently you
need to also pass a `register` command if you don't want to hard-code your
PyPi password on your hard drive.

Unfortunately, `upload` only seems to work for the `sdist` (or `bdist`) it
just generated. The task that I had in mind - manually downloading (or selecting
the snapshot URLs) for the Windows builds to my Linux box, and uploading it
from there - was not available.

The Solution
------------

I decided to poke into how `distutils` or `setuptools` upload stuff to PyPi.
They seem to fill in a monstrous form which looks something like this:


{% highlight python %}
    meta = self.distribution.metadata
    data = {
        # action
        ':action': 'file_upload',
        'protcol_version': '1',

        # identify release
        'name': meta.get_name(),
        'version': meta.get_version(),

        # file content
        'content': (os.path.basename(filename),content),
        'filetype': command,
        'pyversion': pyversion,
        'md5_digest': md5(content).hexdigest(),

        # additional meta-data
        'metadata_version' : '1.0',
        'summary': meta.get_description(),
        'home_page': meta.get_url(),
        'author': meta.get_contact(),
        'author_email': meta.get_contact_email(),
        'license': meta.get_licence(),
        'description': meta.get_long_description(),
        'keywords': meta.get_keywords(),
        'platform': meta.get_platforms(),
        'classifiers': meta.get_classifiers(),
        'download_url': meta.get_download_url(),
        # PEP 314
        'provides': meta.get_provides(),
        'requires': meta.get_requires(),
        'obsoletes': meta.get_obsoletes(),
        }
    comment = ''
    if command == 'bdist_rpm':
        dist, version, id = platform.dist()
        if dist:
            comment = 'built for %s %s' % (dist, version)
    elif command == 'bdist_dumb':
        comment = 'built for %s' % platform.platform(terse=1)
    data['comment'] = comment

    if self.sign:
        data['gpg_signature'] = (os.path.basename(filename) + ".asc",
                                 open(filename+".asc").read())

    # set up the authentication
    auth = "Basic " + standard_b64encode(self.username + ":" +
                                         self.password)

    # Build up the MIME payload for the POST data
    boundary = '--------------GHSKFJDLGDS7543FJKLFHRE75642756743254'
    sep_boundary = '\n--' + boundary
    end_boundary = sep_boundary + '--'
    body = StringIO.StringIO()
    for key, value in data.items():
        # handle multiple entries for the same name
        if not isinstance(value, list):
            value = [value]
        for value in value:
            if isinstance(value, tuple):
                fn = ';filename="%s"' % value[0]
                value = value[1]
            else:
                fn = ""

            body.write(sep_boundary)
            body.write('\nContent-Disposition: form-data; name="%s"'%key)
            body.write(fn)
            body.write("\n\n")
            body.write(value)
            if value and value[-1] == '\r':
                body.write('\n')  # write an extra newline (lurve Macs)
    body.write(end_boundary)
    body.write("\n")
    body = body.getvalue()

    self.announce("Submitting %s to %s" % (filename, self.repository), log.INFO)

    # build the Request
    headers = {'Content-type':
                    'multipart/form-data; boundary=%s' % boundary,
               'Content-length': str(len(body)),
               'Authorization': auth}

{% endhighlight %}

Rather than trying to invent that monstrosity, I simply decided to use it
myself.

To do this, I needed to get a properly formed `upload` object. The inheritance
diagram looks something like:

    Command (distutils/config.py)
        PyPIRCCommand (distutils/config.py)
            upload (distutils/command/upload.py)

In order to get a `Command`, we need to pass it a `Distribution` object. This
`Distribution` object (defined in `distutils/dist.py`) is initialized simply
with a dictionary of attributes. The most common way this object is actually
initialized is by using the normal `setup` function from `distutils.core`.

The `setup` function takes some `**kwargs`; does some various initialization
and then instantiates the `Distribution` class (or a subclass thereof) with
the appropriate attributes.

To make my own `Distribution` object, I simply did this

{% highlight python %}

d = {}
for k in config.options('dist'):
    d[k] = config.get('dist', k)


d['version'] = dist.cbrel.relvers

print "Release:", dist.cbrel.relvers

if d['classifiers']:
    d['classifiers'] = [x for x in d['classifiers'].split('\n') if x]

c = upload(Distribution(d))

{% endhighlight %}


