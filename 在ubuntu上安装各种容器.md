# docker记录

## 常用命令
```
镜像
sudo docker images
sudo docker rmi xxx
sudo docker pull xxx

容器
sudo docker ps -a

sudo docker restart xxx
sudo docker stop xxx
sudo docker rm xxx

sudo docker logs kafka
sudo docker exec -it kafka bash
```

## wurstmeister kafka docker image

- 依赖 wurstmeister zookeeper image

```
1.拉镜像
sudo docker pull wurstmeister/zookeeper
sudo docker pull wurstmeister/kafka

2.启动zookeeper
sudo docker run -d --name zookeeper -p 2181:2181 -t wurstmeister/zookeeper

3.启动kafka
sudo docker run -d --name kafka \
-p 9092:9092 \
-e KAFKA_BROKER_ID=0 \
-e KAFKA_ZOOKEEPER_CONNECT=192.168.12.128:2181 \
-e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://192.168.12.128:9092 \
-e KAFKA_LISTENERS=PLAINTEXT://0.0.0.0:9092 wurstmeister/kafka
```

- 常用命令
```
1.展示topic列表
sudo docker exec -it kafka kafka-topics.sh --list --bootstrap-server 192.168.12.128:9092

2. 创建topic
sudo docker exec -it kafka kafka-topics.sh --create --bootstrap-server 192.168.12.128:9092 --replication-factor 1 --partitions 1 --topic kafkatest

3.produce,会进入交互Ctrl-C退出
sudo docker exec -it kafka kafka-console-producer.sh --broker-list 192.168.12.128:9092 --topic kafkatest

4.consume
sudo docker exec -it kafka kafka-console-consumer.sh --bootstrap-server 192.168.12.128:9092 --topic kafkatest --from-beginning
```

## mysql docker image

1. 准备配置文件（可以先起一个mysql容器，然后进去把/etc/mysql目录复制出来，然后再删除即可）
```
文件注释里面都有
my.cnf: The MySQL  Server configuration file.
mysql.cnf: The MySQL  Client configuration file.

etc
└── mysql
    ├── conf.d
    │   ├── docker.cnf
    │   └── mysql.cnf
    ├── my.cnf
    └── my.cnf.fallback
```

2. 将配置文件挂载到容器内 /etc/mysql 下
```
sudo docker run -d --name mysql -p 3306:3306 \
-v /home/san33/docker/mysql/etc/mysql:/etc/mysql \
-v /home/san33/docker/mysql/logs:/var/log/mysql \
-v /home/san33/docker/mysql/data:/var/lib/mysql \
-e MYSQL_ROOT_PASSWORD=test123 \
mysql:latest
```

## redis docker image

1. 准备配置文件
```
修改redis.conf

1. bind 127.0.0.1 -::1 注释掉该行,因为redis默认只允许localhost访问
2. requirepass test123 因为有 protected-mode 保护模式存在，所以还需要设置密码
```

2. 启动命令，将redis的配置文件挂载进去

```
sudo docker run -d -p 6379:6379 --name redis \
-v /home/san33/docker/redis/redis.conf:/etc/redis/redis.conf \
-v /home/san33/docker/redis/data:/data \
redis:latest redis-server /etc/redis/redis.conf
```


## FAQ

1. 容器端口访问不通...

```
关闭防火墙，请求被防火墙拦截了

ubuntu 关闭防火墙：sudo ufw disable
注意：即使使用 sudo ufw status 查看防火墙状态时 inactive 也要执行disable，不然仍旧不能连接(暂不清楚细节)
```

2. -d 启动容器之后,stop是停不下来的

```
sudo ps -ef | grep kafka
sudo kill -9 kafka对应的PID
删除进程之后,容器则会处于异常,删除即可
```