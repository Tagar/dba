iops1 <- read.csv('mytest_20141009_1755_iops.csv', skip=6)[2:21]
mbps1 <- read.csv('mytest_20141009_1755_mbps.csv', skip=6)[2:21]
lat1  <- read.csv('mytest_20141009_1755_lat.csv', skip=6)[2:21]

iops2 <- read.csv('mytest2_20141010_1034_iops.csv', skip=6)[2:21]
mbps2 <- read.csv('mytest2_20141010_1034_mbps.csv', skip=6)[2:21]
lat2  <- read.csv('mytest2_20141010_1034_lat.csv', skip=6)[2:21]

iops3 <- read.csv('mytest_20141011_2050_iops.csv', skip=6)[2:21]
mbps3 <- read.csv('mytest_20141011_2050_mbps.csv', skip=6)[2:21]
lat3  <- read.csv('mytest_20141011_2050_lat.csv', skip=6)[2:21]

library('plot3D')
par(mfrow = c(2, 1))

oriondraw <- function (z, main, zlab, x=9,y=20, phi=10,theta=-35) {
	yv <- as.vector(t(z))
	ribbon3D(x=1:x,y=1:y, z=z, main=main, xlab="large",ylab="small",zlab=zlab
			, ticktype="detailed", bty="g", phi=phi,theta=theta
			, sub=paste("Mean =", round(mean(yv), digits=1)
			         , " StdDev =", round(sd(yv), digits=1) 
					 , " Min =", round(min(yv), digits=1) 
					 , " Max =", round(max(yv), digits=1) 
					 )
			)
}

pdf("ORION tests on - Storage IOPS.pdf")
oriondraw(z=iops1, main="IOPS - Thu evening", zlab="IOPS", theta=35)
oriondraw(z=iops2, main="IOPS - Fri work hours", zlab="IOPS", theta=35)
oriondraw(z=iops3, main="IOPS - Sat evening", zlab="IOPS", theta=35)
dev.off()

pdf("ORION tests on - Storage throughputness.pdf")
oriondraw(x=8, z=mbps1, main="MBPS - Thu evening", zlab="MBPS")
oriondraw(x=8, z=mbps2, main="MBPS - Fri work hours", zlab="MBPS")
oriondraw(x=8, z=mbps3, main="MBPS - Sat evening", zlab="MBPS")
dev.off()

pdf("ORION tests on - Storage latencies.pdf")
oriondraw(z=lat1, main="Latencies - Thu evening", zlab="Latency, us")
oriondraw(z=lat2, main="Latencies - Fri work hours", zlab="Latency, us", phi=25)
oriondraw(z=lat3, main="Latencies - Sat evening", zlab="Latency, us", phi=25)
dev.off()
