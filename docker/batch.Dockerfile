# Copyright 2022 Google LLC

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     https://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
FROM gcr.io/llm-containers/cluster-provision-image:release

RUN apt-get -yq install jq python3-distutils

RUN wget https://bootstrap.pypa.io/get-pip.py; python3 get-pip.py
RUN pip3 install yq

COPY scripts/train/run_batch.sh .