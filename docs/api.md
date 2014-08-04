# Vcrepo API Docs

**The API is a work in progress and is subject to change!**

## Overview
The Vcrepo API is a REST(ish) API, that, as far is appropriate, follows the collection/resource/action
convention.  At this stage it only implements the GET verb as its easier to deal with when the requirements
to send data with the request are very light.

## Navigation

### Entry Point
The entry point for all API based operations is /api.  Any request that is not in this space, will be treated
as a request to navigate the repositories.

### Data Format
All responses are serialised as JSON.  All returns will be an array at the top level regardless of the number of objects returned.
I.e. where there is only one object in a collection, or the request was for a specific resource, the return will be an array with one elemement.

### Collections
Collections for a resource type will return an aray of hashes.  Each hash representing a resource in the collection.  The hash will have an 'id' field
identifying the object and a 'href' field with a fully qualified URL to that resource.

### Resources
Resources will return an array with one hash that describes the resource.  The fields in the hash will vary depending on the resource type.  In addition, it may contain 'links' and/or 'actions.
'links' will be an array of hashes representing a sub-collections relative to this resource.  Each hash will look like an object in a Collection dexcribed above.  'Actions' also looks
like a collection, but tasks or processes that can be triggered on the resource.

### Actions
Actions trigger a process on a resource.  The response is generally an indication of success (which should be acoompanied by a 200 HTTP response code) or failure (which will be accompanied by
a 40X HTTP response).

## Examples

### See All The Repositories

```
http://localhost/api/repository
```
yields, for example:

```json
    [
       {
           "id": "rhel6-x86_64-puppet_products",
           "href": "http://localhost/api/repository/rhel6-x86_64-puppet_products"
       },
       {
           "id": "rhel6-x86_64-gitlab",
           "href": "http://localhost/api/repository/rhel6-x86_64-gitlab"
       },
       {
           "id": "rhel6-x86_64-updates",
           "href": "http://localhost/api/repository/rhel6-x86_64-updates"
       },
       {
           "id": "rhel7-x86_64-updates",
           "href": "http://localhost/api/repository/rhel7-x86_64-updates"
       }
    ]
```

### See a Specific Repository

```
http://localhost/api/repository/rhel6-x86_64-puppet_products
```

yields, for example:

```json
    [
       {
           "id": "rhel6-x86_64-puppet_products",
           "name": "rhel6-x86_64-puppet_products",
           "source": "http://yum.puppetlabs.com/el/6/products/x86_64/",
           "type": "yum",
           "dir": "/tmp/repos/yum/rhel6-x86_64-puppet_products",
           "enabled": true,
           "links":
           [
               {
                   "id": "commit",
                   "href": "http://localhost/api/repository/rhel6-x86_64-puppet_products/commit"
               },
               {
                   "id": "tag",
                   "href": "http://localhost/api/repository/rhel6-x86_64-puppet_products/tag"
               },
               {
                   "id": "branch",
                   "href": "http://localhost/api/repository/rhel6-x86_64-puppet_products/branch"
               }
           ],
           "actions":
           [
               {
                   "id": "sync",
                   "href": "http://localhost/api/repository/rhel6-x86_64-puppet_products/sync"
               }
           ]
       }
    ]
```

## Actions

Following outlines actions that require additional parameters.  If an action is not called out here
but apears in the API response for a resource, then it needs no additional paramaters and can be called
as is.

### Tag a Commit
Commit resources have an action called tag.  It allows us to tag a specific commit with an arbitrary name
that can be used as a revision for the repository.

Requires:
   - tag_name - the name of the tag to create.

Optional:
   - tagger  - If you want to create an annotated tag, this will be the tagger name (requires 'message')
   - message - If you want to create an annotated tag, this will be the annotation message (requires 'tagger')

Example:
```
http://localhost/api/repository/rhel6-x86_64-puppet_products/commit/343c8da5e435f9ed458b5e43b84cba5bee5b8422/tag?tag_name=production&tagger=chris&message=this_is_prod
```
