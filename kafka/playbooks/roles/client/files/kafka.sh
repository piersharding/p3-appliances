export PATH=/opt/kafka/bin:$PATH

# Kafka home
export KAFKA_HOME="${KAFKA_HOME:-/opt/kafka}"

# add the JMX agent 
#export KAFKA_OPTS="$KAFKA_OPTS -javaagent:${KAFKA_HOME}/libs/jmx_prometheus_javaagent.jar=7071:${KAFKA_HOME}/config/kafka-0-8-2.yml"


