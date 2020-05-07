## Running a DNS Server in Docker

O Docker é uma plataforma de contêineres que ganhou popularidade nos últimos anos. Ele está sendo muito usado para acelerar o processo de desenvolvimento e implantação, imitando o ambiente de produção localmente.

Em um cenário de desenvolvimento de sistemas distribuídos, vários aplicativos podem realizar chamadas entre si (por exemplo, por meio de APIs RESTful) para se comunicar. Na maioria dos casos, essas chamadas usariam host local como nome de domínio, pois o host seria a própria máquina local.

A resolução de nomes nos ambientes Linux é descrita no arquivo /etc/nsswitch.conf. Por padrão, ele possui uma entrada com arquivos dns, o que significa que primeiro verificará o arquivo /etc/hosts e, em seguida, o servidor DNS.

O sistema de nomes de domínio (DNS) é um serviço que converte nomes de domínio em endereços IP e, neste artigo, haverá uma breve visão geral de como executar um servidor DNS em um contêiner do Docker.

Docker network


A primeira etapa seria criar uma rede Docker. Também é possível usar a rede padrão criada durante a instalação, mas não será possível atribuir um endereço IP estático ao seu contêiner. O comando a seguir cria uma rede arbitrária chamada nginx-proxy com intervalo 10.5.0.0/16. Isso nos permitirá executar contêineres com IPs estáticos.

```

$ docker network create --driver=bridge --subnet=10.5.0.0/16 --gateway=10.5.0.1 nginx-proxy 


```

---
BIND9


Existem muitos servidores de nomes disponíveis, mas uma escolha popular é o BIND9. É um servidor de nomes de código aberto e simples de configurar.

O primeiro arquivo a configurar é o named.conf.options:

```
//ACLs (Access Control Lists)
 
// ACL "permite-recursiva" vao ficar os hosts estao autorizados a fazer  
// consultas recursivas atraves deste servidor. 
acl permite-recursiva {
        127.0.0.1;
        ::1;
        250.250.0.0/23;
        192.168.0.0/16;
        172.16.0.0/12;
        10.0.0.0/8;
};
 
options {
    // O diretorio de trabalho do servidor 
    // Quaisquer caminho nao informado sera tomado como  padrao este directorio 
    directory "/var/cache/bind";
 
    //Suporte a DNSSEC
    dnssec-enable yes;
    dnssec-validation auto;
 
    // Conforme RFC1035
    // https://www.ietf.org/rfc/rfc1035.txt
    auth-nxdomain no;
 
    // Respondendo para IPv4 e IPv6
    // Porta 53 estara aberta para ambos v4 e v6 
    listen-on { any; };
    listen-on-v6 { 127.0.0.1; };
 
    // Limitacao da taxa de resposta no sistema de nomes de domonio (DNS RRL) 
    //rate-limit {
     //   responses-per-second 15;
    //    window 5;
   // };
 
    // Melhora o desempenho do servidor, reduzindo os volumes de dados de saida. 
    // O padrao BIND a (no) nao. 
    minimal-responses yes;
 
    // Especifica quais hosts estao autorizados a fazer consultas  
    // recursivas atraves deste servidor. 
    // Aqui que voce vai informar os IPs da sua rede que voce ira permitir consultar os DNS. 
    allow-recursion {
        permite-recursiva;
    };
 
    // Endereco estao autorizados a emitir consultas ao cache local, 
    // sem acesso ao cache local as consultas recursivas sao inateis. 
    allow-query-cache {
        permite-recursiva;
    };
 
    // Especifica quais hosts estao autorizados a fazer perguntas DNS comuns. 
    allow-query { any; };
 
    // Especifica quais hosts estao autorizados a receber transferencias de zona a partir do servidor. 
    // Seu servidor Secundario, no nosso caso vou deixar entao o ips dos dois servidores v4 e v6. 
    allow-transfer {
        10.5.0.6;
        
    };
    also-notify {
        10.5.0.6;
        
    };
 
    // Esta opcao faz com que o servidor slave ao fazer a transferencia de zonas 
    // mastes deste servidor nao compile o arquivo, assim no outro servidor o arquivo 
    // da zona tera um texto "puro" 
    masterfile-format text;
 
    // Para evitar que vase a versao do Bind, definimos um nome
    version "RR DNS Server";
};

```


Ele descreve configurações básicas como encaminhadores, interface para escutar e armazenar em cache o diretório. Neste exemplo, o DNS do Google é usado como encaminhador.

Em seguida, a zona chamada inmanager.com.br é criada e aponta para um arquivo chamado /etc/bind/zones/db.inmanager.com.br. É definido no arquivo named.conf.local:
  
```
//include "/etc/bind/named.conf.default-zones";
//include "/etc/bind/named.conf.rfc1918";

zone "inmanager.com.br" {
    file "/etc/bind/db.inmanager.com.br";
    type master;
    notify yes;
    also-notify { 10.5.0.6; };
    allow-transfer { 10.5.0.6; };
};

//zone "4.3.2.1.in-addr.arpa" {
//    type master;
//    file "/var/cache/bind/1.2.3.4.rev";
//    notify yes;
//};

```

Agora, um arquivo chamado db.inmanager.com.br com todos os hosts (por exemplo, serviços em execução nos contêineres do Docker) será definido:
  
```
$TTL 8h ; 
@	IN	SOA	ns1.inmanager.com.br. root.inmanager.com.br. ( 
			2017071101 ; serial 
			3h ; refresh 
			30m ; retry 
			4d ; expiry 
			1h ; negative cache 
); 
@			IN		NS	ns1.inmanager.com.br. 
@			IN		NS	ns2.inmanager.com.br. 
@			IN		MX	5 mail.inmanager.com.br. 
ns1			IN		A	10.5.0.5 
ns2			IN		A	10.5.0.6
host1		IN		A	10.5.0.8  
host2		IN		A	10.5.0.9
  
www			IN		A	10.10.10.7 
web			IN		CNAME	www 
ftp			IN		CNAME	www 
firewall 	IN		A	10.10.10.1 
proxy		IN		CNAME	firewall 
mail	  	IN		A	10.10.10.3 
smtp		IN 		CNAME	mail 
imap	 	IN  	CNAME	mail 
pop3	 	IN  	CNAME	mail

```


No exemplo, existem dois hosts host1.inmanager.com.br e host2.inmanager.com.br e um servidor de nomes ns1.inmanager.com.br. Faça as alterações necessárias para ajustar sua rede e domínios do Docker.

A próxima etapa é a imagem do Docker:


```
FROM ubuntu:bionic

RUN apt-get update \
  && apt-get install -y \
  bind9 \
  bind9utils \
  bind9-doc \
  dnsutils \
  wget \
  nano \
  sudo \
  iputils-ping \
  -o Dpkg::Options::="--force-confold" 

# Enable IPv4
RUN sed -i 's/OPTIONS=.*/OPTIONS="-4 -u bind"/' /etc/default/bind9

# RUN mkdir /var/log/named/ && chown bind. /var/log/named/ 

RUN mkdir -m 0770 -p /etc/bind && chown -R root:bind /etc/bind ; \
    mkdir -m 0770 -p /var/cache/bind && chown -R bind:bind /var/cache/bind ; \
    wget -q -O /etc/bind/bind.keys https://ftp.isc.org/isc/bind9/keys/9.11/bind.keys.v9_11 ; \
    rndc-confgen -a

COPY configs/. /etc/bind/

RUN mkdir /var/run/named

VOLUME ["/etc/bind"]
VOLUME ["/var/cache/bind"]

COPY entrypoint.sh /
ENTRYPOINT ["/entrypoint.sh"]

# Run eternal loop
CMD ["/bin/bash", "-c", "while :; do sleep 10; done"]

```


Salve todos os arquivos de configuração no mesmo diretório, incluindo o Dockerfile.
---
Running


Primeiro, crie a imagem do Docker. Neste exemplo, o nome é bind9:

```
$ sudo docker build -t bind9 .
```

Execute um contêiner em segundo plano, usando o mesmo IP do arquivo db.inmanager.com.br e a mesma rede Docker criada

```
$ sudo docker run -d --rm --name=dns-server --net=nginx-proxy --ip=10.5.0.5 --dns=10.5.0.5 --dns=10.5.0.6 bind9
```

Ative o daemon bind9:

```
$ sudo docker exec -d dns-server /etc/init.d/bind9 start
```

Agora é possível executar os dois hosts usando o contêiner dns-server como um servidor DNS:

```
$ sudo docker run -d --rm --name=host1 --nginx-proxy --ip=10.5.0.8 --dns=10.5.0.5 bind9 /bin/bash -c "while :; do sleep 10; done" 
$ sudo docker run -d --rm --name=host2 --nginx-proxy --ip=10.5.0.9 --dns=10.5.0.5 bind9 /bin/bash -c "while :; do sleep 10; done"

```


Dentro do contêiner, é possível verificar se o host2 está acessível a partir do host1, usando o DNS:

```
$ sudo docker exec -it host1 bash
```

A saída do comando ping é a seguinte:

```
root@4c4178369feb:/# ping host2.inmanager.com.br 
PING host2.inmanager.com.br (10.5.0.9) 56(84) bytes of data. 
64 bytes from host2.inmanager.com.br (10.5.0.9): icmp_seq=1 ttl=64 time=0.148 ms 
64 bytes from host2.inmanager.com.br (10.5.0.9): icmp_seq=2 ttl=64 time=0.101 ms 
64 bytes from host2.inmanager.com.br (10.5.0.9): icmp_seq=3 ttl=64 time=0.112 ms 
^C 
--- host2.inmanager.com.br ping statistics --- 
3 packets transmitted, 3 received, 0% packet loss, time 2055ms 
rtt min/avg/max/mdev = 0.101/0.120/0.148/0.022 ms 
root@4c4178369feb:/#
```