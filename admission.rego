package system

import data.vuln.attributes as vuln

main = {
    "apiVersion": "admission.k8s.io/v1",
    "kind": "AdmissionReview",
    "response": response,
}

default uid = ""

uid = input.request.uid

response = {
    "allowed": false,
    "uid": uid,
    "status": {
        "reason": reason,
    },
} {
    reason = concat(", ", deny)
    reason != ""
}
else = {"allowed": true, "uid": uid}

deny[msg] {
    input.request.kind.kind == "Deployment"
    some image
      image = input.request.object.spec.template.spec.containers[_].image
      crits := vuln[image].crit
      crits > 0
      msg := sprintf("Image '%s' has more than 0 critical vulnerabilities (%d)", [image, crits])
}

deny[msg] {
    input.request.kind.kind == "Deployment"
    containers := input.request.object.spec.template.spec.containers[_]
    not startswith(containers.image, "trusted/")
    msg := sprintf("Image '%s' is not from a trusted repo", [containers.image])
}
