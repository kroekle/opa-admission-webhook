# OPA Admission Webhook example

This is an example of setting up OPA as an admission webhook in Kubernetes.  The examples will use minikube, but should work with any Kubernetes.  This example was written against Kubernetes v1.20.0.  This project is licensed under the terms of the Apache2 license.  The author holds no responsibility for the use.

## Target Audience

The target audience for this demo is Engineers and System Administrators that want to learn the basics of setting up Kubernetes Admission Webhooks with OPA

## Acknowledgements

Much of this demo is drawn from the documentation from [OPA ingress Tutorial](https://www.openpolicyagent.org/docs/latest/kubernetes-tutorial/) and [Dynamic Admission Control](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/)

## Prerequisites
A basic understanding of Kubernetes and the kubectl command.

[kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

[Minikube](https://minikube.sigs.k8s.io/docs/start/)

[openssl](https://www.openssl.org/)

## Cluster setup
### Create a new minikube cluster
If you're using minikube, I recommend using a new local profile.  To startup a new cluster with a non-default profile (unless you are blessed with endless memory, you will want to stop any other minikube clusters first):

```
 minikube start -p admission
 ```

### Kubectl config
If you used minikube to just create your cluster, kubectl should be configured for that cluster.  You can check what cluster kubectl is configured with using this command:

```
kubectl config get-contexts
```

And to use a context (substitute your context if using something different):
```
kubectl config use-context admission
```

 ### Create a new namespace for OPA
 ```
 kubectl create namespace opa
 ```

 ### Create TLS CA and Certificate/key pair
 Communication between the Kubernetes Admission Controller and OPA must be over TLS.  You can use the following commands to create the TLS key and cert for the CA:

 ```
 openssl genrsa -out ca.key 2048
 openssl req -x509 -new -nodes -key ca.key -days 100000 -out ca.crt -subj "/CN=admission_ca"
 ```

 You will now have two files in your working folder, ca.key & ca.crt.

 Next create a file named server.conf with the following contents:

 ```
 [req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
prompt = no
[req_distinguished_name]
CN = opa.opa.svc
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = opa.opa.svc
 ```

An item of note, if you give you OPA a different service name below you will need to change the common name (CN) and Subject Alt Name (DNS.1=).

Now we generate the TLS key and cert for OPA

```
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr -config server.conf
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 100000 -extensions v3_req -extfile server.conf
```

You will now have 3 additional files in your working folder, server.key, server.csr, & server.crt.

### Store TLS cert/key pair in cluster
We will add the certificate/key pair to the cluster as a kubernetes secret.  (be sure you create this in the opa namespace)

```
kubectl --namespace=opa create secret tls opa-server --cert=server.crt --key=server.key
```

### Create OPA service/deployment

Standard service and deployment.  Note we are mounting the secret we created above as a volume mount.

This yaml can also be found in opa.yaml.

```
kind: Service
apiVersion: v1
metadata:
  name: opa
  namespace: opa
spec:
  selector:
    app: opa
  ports:
  - name: https
    protocol: TCP
    port: 443
    targetPort: 8443
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: opa
  namespace: opa
  name: opa
spec:
  replicas: 1
  selector:
    matchLabels:
      app: opa
  template:
    metadata:
      labels:
        app: opa
      name: opa
    spec:
      containers:
        # WARNING: OPA is NOT running with an authorization policy configured. This
        # means that clients can read and write policies in OPA. If you are
        # deploying OPA in an insecure environment, be sure to configure
        # authentication and authorization on the daemon. See the Security page for
        # details: https://www.openpolicyagent.org/docs/security.html.
        - name: opa
          image: openpolicyagent/opa:latest-rootless
          args:
            - "run"
            - "--server"
            - "--tls-cert-file=/certs/tls.crt"
            - "--tls-private-key-file=/certs/tls.key"
            - "--addr=0.0.0.0:8443"
            - "--addr=http://127.0.0.1:8181"
            - "--log-format=json-pretty"
            - "--set=decision_logs.console=true"
          volumeMounts:
            - readOnly: true
              mountPath: /certs
              name: opa-server
          readinessProbe:
            httpGet:
              path: /health?plugins&bundle
              scheme: HTTPS
              port: 8443
            initialDelaySeconds: 3
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              scheme: HTTPS
              port: 8443
            initialDelaySeconds: 3
            periodSeconds: 5
      volumes:
        - name: opa-server
          secret:
            secretName: opa-server
```

```
kubectl apply -f opa.yaml
```

### Confirm good running OPA

At this point we can confirm that our opa server is running correctly.  As noted in the deployment manifest above, this is not a secured endpoint, which is good our our basic example, but not appropriate for any cluster you would have running with workloads.

Let's setup a port forward:

```
kubectl port-forward --namespace opa service/opa 9999:443 &
```

Then test the health endpoint.  Curl does not know about the CA that you created earlier so you will either need to ignore cert errors or add the service host name to your /etc/hosts file and provide the ca.crt to curl (which is really too much effort for a cert error)

```
curl --insecure -v https://localhost:9999/health
```
or
```
sudo sh -c 'echo 127.0.0.1  opa.opa.svc >> /etc/hosts'
curl --cacert ca.crt -v https://opa.opa.svc:9999/health
```

The health endpoint returns and empty json object and a http status of 200 if healthy

#### Add a policy to the OPA

At this point we should have a healthy OPA that we can apply some polices to.  OPA has APIs to add policies and data.

The policy below will just add a couple of simple rules.  I've included this in one file for ease of reading, but you would normally separate the deny rules into their own package and import them.

```
<admission.rego>
```

Use the put method when writing policies.  "Admission" is just a path to the policy, you can go deeper paths if you like and make it whatever you like.

```
curl -X PUT -T admission.rego --insecure -H 'Content-Type: text/plain' https://localhost:9999/v1/policies/admission
```

TODO: add data load

You can now test the document by using some example inputs. (these are not full AdmissionReview documents, but just the necessities to get a decision)

A good example:

```
curl -X POST -T good.json --insecure -H 'Content-Type: application/json' https://localhost:9999/v1/data/system/main
```

Notice the path, we evaluate the policy through the data api and we use the package/rule as the path.  Interestingly enough, we could evaluate the entire package by dropping off the rule:

```
curl -X POST -T good.json --insecure -H 'Content-Type: application/json' https://localhost:9999/v1/data/system
```

We can also test each of the rules with bad documents:

```
curl -X POST -T bad-repo.json --insecure -H 'Content-Type: application/json' https://localhost:9999/v1/data/system/main
curl -X POST -T bad-crit.json --insecure -H 'Content-Type: application/json' https://localhost:9999/v1/data/system/main
curl -X POST -T bad-both.json --insecure -H 'Content-Type: application/json' https://localhost:9999/v1/data/system/main
```

Notice that when both conditions are met, we get both messages in the reason

### Fire the missiles 

We are ready to actually create and add the validating webhook configuration.  Because the configuration needs the cert we created earlier it will be easier if we just create the file (vs giving you a prepackaged file):

```
cat > webhook-configuration.yaml <<EOF
kind: ValidatingWebhookConfiguration
apiVersion: admissionregistration.k8s.io/v1
metadata:
  name: opa-validating-webhook
webhooks:
  - name: validating-webhook.openpolicyagent.org
    admissionReviewVersions: ["v1", "v1beta1"]
    sideEffects: None
    namespaceSelector:
      matchExpressions:
      - key: openpolicyagent.org/webhook
        operator: NotIn
        values:
        - ignore
    rules:
      - operations: ["CREATE", "UPDATE"]
        apiGroups: ["*"]
        apiVersions: ["*"]
        resources: ["*"]
    clientConfig:
      caBundle: $(cat ca.crt | base64 | tr -d '\n')
      service:
        namespace: opa
        name: opa
EOF
```

You will notice that we are including all api group/versions and all top level resources.  You could choose to narrow the resources to your use case, for example if you just want to look at pods then you could use "pods/*".  Also, we are just capturing the create and update operations, you may need more for yours, you can get the details of these on the Dynamic Admission Control link I provided above.

The other thing to note is that we are adding a namespace selector that will exclude namespace with a certain label.  We will use this in the classic "do as I say and not as I do" and exclude the opa namespace (along with kube-system).  There is actually good reason for this, if you make a policy that would exclude the opa from starting itself up (on a pod death for example), you could get your cluster in a state that you may not get anything into the cluster.

Let's add these labels now.

```
kubectl label ns kube-system openpolicyagent.org/webhook=ignore
kubectl label ns opa openpolicyagent.org/webhook=ignore
```

Now it's time to add the webhook.

```
kubectl apply -f webhook-configuration.yaml
```

Now if all has gone to plan you have a working webhook with OPA making the decisions.  If not, remember I take no liability, you were testing on a test cluster correct?

### Prove that it's working

Go ahead in kick the tires.  There are three sample yamls, crit.yaml, untrusted.yaml, and good.yaml.  The first two will fail the webhook when applied (the third one is not using a real image, but will add the deployment and pod).

```
kubectl apply -f crit.yaml
kubectl apply -f untrusted.yaml
kubectl apply -f good.yaml
```

The errors should look something like this:

```
Error from server (Image 'untrusted/image:v1' is not from a trusted repo): error when creating "untrusted.yaml": admission webhook "validating-webhook.openpolicyagent.org" denied the request: Image 'untrusted/image:v1' is not from a trusted repo
```

BTW, the config file for the OPA is logging all the decisions to the console, so feel free to look at the information (grabbing one of these documents is a good way to test rules). 

### A few important points
* Remember this is an admission webhook, so you if apply it after bad resources are in the cluster the rules will not affect the running resources.  The key here is running resources, pods are know to go away or need to scale, these events will cause the webhook to kick in, so try getting all resources pushed through the api as quickly as practical after applying new rules
* We (or maybe just me) often don't think of deployments/pods/replicasets as separate resources, but they are.  You may think that applying a rule to a pod would be enough, but applying a deployment through the api (e.g. kubectl) will succeed but the pod will fail later.  This is another case where you can get your cluster in a weird state where the deployment template will show the new config, but the pod with show the old.
* Remember this was just an example for learning, other considerations will need to be taken into account for a production system.  Security around the OPA being a big one as well as scaling it up.  

### Cleaning up
Delete you cluster (I told you to use a test cluster).

```
 minikube delete -p admission
```