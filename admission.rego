package system

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
    image := input.request.object.spec.template.spec.containers[_].image
    image == "trusted/api:v1"
    msg := sprintf("Image '%s' has more than 0 critical vulnerabilities (%d)", [image, 7])
}

deny[msg] {
    input.request.kind.kind == "Deployment"
    containers := input.request.object.spec.template.spec.containers[_]
    not startswith(containers.image, "trusted/")
    msg := sprintf("Image '%s' is not from a trusted repo", [containers.image])
}
